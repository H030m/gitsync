# 團隊決策備忘 (MEMORY)

> **不是個人日誌**——這裡只記**會影響別人怎麼寫程式**的決策。個人進度寫 [`journal/<你的名字>.md`](./journal/)。
>
> 最新決策在最上面。

---

## 2026-05-26 — ARCHITECTURE.md 文體規範：實作改寫為敘述

ARCHITECTURE.md 是「給人看 + AI 看」的設計文件，不是 reference implementation。所有 TS / Dart 實作 code 一律改寫為敘述（行為條列、責任清單、輸入輸出 contract）。

**保留 code 的例外**：
- 顏色 / theme token（精確值需要）— §8.1 dart theme
- Firestore Security Rules（DSL 語法精確度需要）— §2.2
- 部署 / 維運指令（`gcloud` / `firebase deploy` 等）— §5.4 / §5.6 / §12
- 設定檔結構範例（`firestore.indexes.json`）— §5.6
- ASCII 圖（不是 code）— §1 / §7.1
- Firestore schema tree（結構化清單）— §2.1

**理由**：實作 code 在 ARCHITECTURE 容易過時、佔篇幅、reviewer 揪不出邏輯漏洞會被困在語法細節。Sprint 1 隊員依敘述自己寫 code，要參考具體寫法去 [`COURSE_METHODS.md`](./COURSE_METHODS.md)。

## 2026-05-26 — `dependsOn` 型別契約：LLM 端用 `number[]` (索引)，Firestore 端用 `string[]` (taskId)

`breakdownTaskFlow` 內部負責翻譯：
- Zod schema 定義 `dependsOn: z.array(z.number().int())`（0-based 索引）
- Step 4：pre-generate taskIds (`tasksCollection.doc().id`)
- Step 5：把 LLM 輸出的索引換成預生成的 taskId
- Step 6：transaction 批次寫入

Flutter 端永遠只看到 `string[]` taskId 版本；**不要把 LLM 原始輸出直接送進前端**。

詳見 [`ARCHITECTURE.md §5.1`](./ARCHITECTURE.md#51-flow-1--breakdowntaskflow任務拆解)。

## 2026-05-26 — `tasks.dependsOn` 必建 array-contains 複合索引

`onTaskUpdated` trigger 反向查下游時用 `where('dependsOn', 'array-contains', taskId)` + `where('status', '==', 'todo')`。沒這個複合索引 trigger 會直接 crash → 下游永不喚醒。

部署前必執行（**使用者**親跑）：
```bash
gcloud firestore indexes composite create \
  --collection-group=tasks \
  --query-scope=COLLECTION_GROUP \
  --field-config field-path=dependsOn,array-config=CONTAINS \
  --field-config field-path=status,order=ASCENDING
```

亦寫入 `firestore.indexes.json`。詳見 [`ARCHITECTURE.md §5.6`](./ARCHITECTURE.md#56-vector-search-索引與預過濾)。

## 2026-05-26 — `users` 必加 `discordUserId` 對照欄位

Discord 訊息存的是 `authorId` (Discord snowflake)，GitHub commit 存的是 `githubLogin`，Firebase Auth 用 UID。沒對照 = AI 生 handoff 時無法把對話中的人連到真實貢獻者，會張冠李戴。

實作：
- `users/{uid}.discordUserId: string?`（APP 設定頁讓用戶填 18 位 snowflake）
- `assignTaskFlow.readTeamState` & `generateHandoffFlow.readTeamRoster` 回傳必含此欄位
- AI Agent 在 draft / handoff 時自行做姓名對齊

詳見 [`ARCHITECTURE.md §2.1 users schema`](./ARCHITECTURE.md#21-collections) + [`§5.2`](./ARCHITECTURE.md#52-flow-2--assigntaskflow動態任務分派) + [`§5.3`](./ARCHITECTURE.md#53-flow-3--generatehandoffflow交接文件)。

## 2026-05-26 — Webhook ↔ Trigger 職責切分：webhook 只寫 raw，trigger 才做 AI

`githubWebhook` 等 HTTP handler **嚴禁** 解析 commit 的 `#N`、算 embedding、跨文件改 task。**只允許** 把 GitHub payload 標準化後寫進對應的 Firestore doc。所有業務語意 / OpenAI 呼叫 / 跨文件 transaction 一律下沉到 `onCommitCreated` / `onPRMerged` 等 trigger 層。

理由：
- webhook 必須毫秒級回應 GitHub（避免外部 retry 風暴），業務邏輯放 trigger 才有 idempotency key 保護
- 兩邊都寫同一邏輯 = 重複計算 + 欄位互蓋

詳見 [`ARCHITECTURE.md §4.3 / §6.3`](./ARCHITECTURE.md#43-firestore-triggers事件驅動)。

## 2026-05-26 — `breakdownTaskFlow` 必須加分散式鎖

兩人同時點「AI 拆解」會跑兩遍 → 同 goal 拆出兩套任務 + 兩倍 GitHub Issue。雙層防護：
- 前端：button disable + loading；callable 回傳前不准重按
- 後端：`repos/{repoId}.isBreakingDown` flag + transaction（鎖定 → 跑 flow → finally 解鎖）
- 兜底：`scheduledUnstickBreakdown` 排程每 10 分鐘掃 `breakdownStartedAt > 5 分鐘前` 強制解鎖

詳見 [`ARCHITECTURE.md §5.1`](./ARCHITECTURE.md#51-flow-1--breakdowntaskflow任務拆解)。

## 2026-05-26 — Discord forwarder 必須帶指數退避 retry

Cloud Functions 冷啟動 1.5–3 秒；Discord 突發多人發言會撞 cold start + 429 → 訊息丟失。Forwarder 端 `sendWithRetry` 規格：
- maxRetries = 4，base 1s，指數退避 + 100–500ms jitter
- 單次 timeout 8s（含冷啟動）
- 4xx 非 429 直接 drop 不重試（避免無謂浪費）

詳見 [`ARCHITECTURE.md §7.2`](./ARCHITECTURE.md#72-inbound--訊息怎麼進-firestore)。

## 2026-05-26 — 所有 Firestore Trigger 必須做 idempotency check

Firestore Trigger 是 **at-least-once** 交付。`FieldValue.increment(1)` 雖然原子，但同一事件被送兩次 = 加兩次。守則：
- 每個 trigger 開頭跑 transaction：(1) get idempotencyKeys/{eventId}，(2) 若已存在直接 return，(3) 否則 mark + 跑業務
- **OpenAI 等外部副作用必須在 transaction 之外做**（否則失敗會被當已處理）
- 對於 commit summary / embedding 這類「掉一兩個沒關係」的功能，接受偶發失敗、提供使用者手動重試按鈕

詳見 [`ARCHITECTURE.md §4.4 規則 C`](./ARCHITECTURE.md#44-併發-race-condition-防禦守則)。

## 2026-05-26 — Discord 訊息要在 forwarder 端先過濾，第二層在 ingest function

不可把所有 Discord 對話盲送進 Firestore + embedding（污染向量庫 + 燒 token）。雙層過濾：
1. **forwarder bot** 端先濾（純表情、`+1`、`ok`、純連結、長度<5、bot 訊息、純貼圖）→ 不送 ingest
2. **`discordMessageIngest`** 端再濾一次（用 `functions/src/tools/discordFilter.ts`，邏輯與 forwarder 同步）

兩層過濾規則必須保持一致；若改規則記得兩邊同改。

## 2026-05-26 — Discord 簡化為「訊息直接寫 Firestore」單向資料源

放棄 Discord slash command 介面（原規劃的 `/gitsync-check` / `/gitsync-daily` / `/gitsync-assign` 全部砍掉）。理由：
- Discord Interactions Webhook 有 3 秒超時硬限制；AI flow 動輒 5–15 秒，必須用 Cloud Tasks 解耦——架構複雜度爆增
- 隊員偏好讓「Discord 純聊天 → 訊息進 Firestore → APP 端整理」的單向流
- 所有「主動操作」改在 APP 內按按鈕（呼 Firebase Callable），不在 Discord

**現況**：
- Inbound：使用者**另外**跑一個小 discord.js forwarder bot（本機/VPS），POST 到 `discordMessageIngest` Cloud Function；不是 Cloud Function 端的責任
- Outbound：`onTaskUpdated` trigger 直接 POST 到 channel webhook URL（無 3 秒問題）

詳見 [`ARCHITECTURE.md §7`](./ARCHITECTURE.md#7-discord-整合簡化版)。

## 2026-05-26 — 併發守則：counter 用 atomic increment、跨欄位用 transaction

GitHub push 10 個 commit 會引發 10 個 `onCommitCreated` 併發。read-modify-write 計數會錯。一律：
- 計數欄位：`FieldValue.increment(±1)`
- 多欄位/跨文件：`db.runTransaction(...)`

詳見 [`ARCHITECTURE.md §4.4`](./ARCHITECTURE.md#44-併發-race-condition-防禦守則)。

## 2026-05-26 — 排程任務必須扇出 (Fan-out)，不可 for-loop

`scheduledDailyReport` 不可 for-loop 跑所有 repo（500 秒 timeout）。排程器只做「掃 repoId 列表 → 投 Cloud Tasks」；每個 repo 由獨立 worker function 處理。

需建立 queue：`gcloud tasks queues create daily-report-queue --location=us-west1`。

## 2026-05-26 — Commit message embedding 前必過濾

自動產生的 commit（`Merge branch ...` / `Bump version` / `v1.2.3`）會污染向量庫又燒 token。`onCommitCreated` 算 embedding 前先過 `shouldSkipEmbedding()` regex 黑名單。

詳見 [`ARCHITECTURE.md §5.6`](./ARCHITECTURE.md#56-vector-search-索引與預過濾)。

## 2026-05-26 — 棄用 Genkit，改用 OpenAI 官方 Node.js SDK

最初計畫沿用課程教的 Genkit，後來改成直接 OpenAI SDK + structured outputs（zod）+ function calling。理由：
- 不為了用課程套件多綁一層
- Function calling 用原生 SDK 比 Genkit 抽象好除錯
- Structured outputs (`response_format`) 已能解決 schema 對齊問題，不需要 Genkit 的 `definePrompt`

詳見 [`ARCHITECTURE.md §0`](./ARCHITECTURE.md#0-技術選型總結) + [`COURSE_METHODS.md §8`](./COURSE_METHODS.md#8-ai-agent--openai-sdk-直接使用後端)。

## 2026-05-26 — Firestore 路徑統一掛 `apps/gitsync/`

所有 collection 開頭都是 `apps/gitsync/...`，沿用課程 `group-todo-list` 範例的命名慣例。**不要寫成根目錄 `users/`、`repos/`**。

## 2026-05-26 — Cloud Functions region 固定 `us-west1`

所有 Functions 都用 `us-west1`，跟課程範例一致。**不要混用 region**——混了 callable 在 Flutter 端會找不到。

## 2026-05-26 — `commits` / `discordMessages` / `pullRequests` 必須冗餘存 `repoId`

Firestore `findNearest` 跨 collection group 搜尋時，必須 `where('repoId', '==', repoId)` 預過濾，否則跨 repo 資料洩漏。**寫入這三個 collection 時 repoId 不能漏**，即使路徑裡已經有了。

詳見 [`ARCHITECTURE.md §5.6`](./ARCHITECTURE.md#56-vector-search-索引與預過濾)。

## 2026-05-26 — `commits` / `pullRequests` / `discordMessages` / `dailyReports` / `members` Client 一律不能寫

Firestore Rules 對這 5 個 collection 設 `allow write: if false`，**只能透過 Cloud Functions (admin SDK 繞過 rules) 寫入**。
- 好處：webhook 來源驗證能徹底集中在 Function 裡，前端寫 bug 也不會污染資料
- 影響：若你想直接 Flutter 端寫，**請先停**——改成呼一個對應的 callable Function

## 2026-05-26 — Discord 長指令 (`gitsync-assign` / `gitsync-daily`) 必須走 Deferred Response

Discord Interactions Webhook 3 秒沒回應 = 「應用程式沒有回應」。AI flow 動輒 5–15 秒，**必須**：
1. 立刻 `res.json({ type: 5 })`（DEFERRED）
2. 背景跑完，PATCH `/webhooks/{appId}/{token}/messages/@original` 補結果

詳見 [`ARCHITECTURE.md §7.2`](./ARCHITECTURE.md#72-discordinteractions-function--3-秒回應限制--deferred-response)。

---

> 每加一條決策時，**同時**：
> 1. 寫日期 + 一句話標題
> 2. 寫理由（為何這樣決定）
> 3. 連到對應的 ARCHITECTURE / METHODS 章節
