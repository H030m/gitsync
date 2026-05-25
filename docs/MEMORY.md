# 團隊決策備忘 (MEMORY)

> **不是個人日誌**——這裡只記**會影響別人怎麼寫程式**的決策。個人進度寫 [`journal/<你的名字>.md`](./journal/)。
>
> 最新決策在最上面。

---

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
