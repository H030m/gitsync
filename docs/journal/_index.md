# 團隊近 7 天動態 (Index)

> 這份檔案由每位 AI / 人在寫完日誌後**自行更新**。最新動態在最上面，超過 7 天的條目自動下移到「歷史」區塊（或直接刪除——repo 有 git 紀錄）。
>
> 開工前必讀。看到「進行中」欄裡有別人正在動的檔案，請避開或先協調。

---

## 進行中（aka 不要碰）

| 隊員 | 在做什麼 | 預計動的檔案 |
|---|---|---|
| 嘉駿 | Discord 整合（模組 B）| `discord-bot/`、`functions/src/handlers/discordMessageIngest.ts` |

> 嘉駿剛把骨架鋪完（Sprint 1）。**接下來各模組隊員就 [`ARCHITECTURE.md §9`](../ARCHITECTURE.md#9-模組職責--隊員分工建議) 開工**，避免動到別人的層；如要跨層改動先在這列出。

---

## 2026-06-02

- **嘉駿 — Discord bot 上線 + 接收 probe**：建好 Discord application（Guild Install、唯讀權限、開 Message Content Intent）並邀請進伺服器；新增 `discord-bot/src/probe.ts`（只需 token 的連通性探針，`npm run probe`）。實測 probe 登入成功並收到 DC 訊息印在 terminal（`#幹話`/`#會議記錄` 中文內容正確）。端到端 ingest（bot→Function→Firestore）尚未測，trellis 工作 `06-02-discord-bot-live-setup` 仍 in_progress。詳見 [113062210_chiajun.md](./113062210_chiajun.md)。
- **嘉駿 — Discord forwarder bot + ingest 完工**：新建 `discord-bot/`（discord.js v14 TS 套件，抓 mapped channel 訊息→第一道過濾→指數退避 POST）+ 補完 `discordMessageIngest` Cloud Function（驗 payload→第二道過濾→`create()` 原子寫入兼 messageId 去重）。雙層過濾 + 去重防垃圾塞爆。typecheck/build 0 error、filter smoke test 12/12。`onDiscordMessageCreated`（embedding/AI 連 task）仍 stub。詳見 [113062210_chiajun.md](./113062210_chiajun.md) 2026-06-02 那篇。

## 2026-05-27

- **嘉駿 — Fake backend 模式上線**：`--dart-define=BACKEND=fake` 切換；Repository / AuthService / FunctionsService 全部 abstract + Live + Fake；UI 不需要 Firebase / OpenAI / GitHub 就能跑。Region 同步從 us-west1 改 asia-east1（對齊 Firestore 台灣 region）。詳見 [113062210_chiajun.md](./113062210_chiajun.md) 2026-05-27 那篇。

## 2026-05-26

- **嘉駿 (113062210) — Sprint 1 骨架完工**：lib/ 五層 MVVM (theme/models×9/repositories×9/services×5/view_models×8/router/views×11/main.dart) + functions/ TS (handlers×12, triggers×7, flows×4, prompts×4, tools×5, services×1, config/types/admin/index) + secrets/ 中央倉 (含 README + *.env.example) + firestore.rules / indexes / firebase.json。`flutter analyze` 0 warn、`tsc --noEmit` 0 error。**所有 flow 是 stub**（`throw new Error('not implemented yet')`），各模組隊員只要往對應檔案補 OpenAI 呼叫即可。詳見 [113062210_chiajun.md](./113062210_chiajun.md) 2026-05-26 16:50 那篇。
- 初始化專案文件結構，建立 `docs/journal/` 與五人 journal 初始檔。
- 架構師 review pass：併發守則 (§4.4)、排程扇出 (§5.4)、commit filter (§5.6)、Discord 簡化為「訊息直寫 Firestore」(§7) — 全數寫入 ARCHITECTURE.md + MEMORY.md。
- 第二輪 review：補強 §4.4 Rule C（trigger at-least-once → in-trigger idempotency 強制）、§7 forwarder + ingest 雙層 Discord 訊息過濾、§10 Sprint 4 與簡化版 Discord 對齊。
- 第三輪 review：§5.1 breakdownTask 分散式鎖（isBreakingDown + 兜底排程）、§6.3 ↔ §4.3 職責切分（webhook 只寫 raw，trigger 才做 AI）、§7.2 forwarder 指數退避 retry、§11 風險表全面更新。
- 第四輪 review（docs/issue.txt）：§5.1 補 Step 4-6 索引→taskId 翻譯、§5.6 補 tasks.dependsOn array-contains 複合索引、§2.1 users 加 discordUserId 欄位、§5.2/§5.3 tool 餵 AI 三組身份對照。
- 文體規範：ARCHITECTURE.md 內所有 TS/Dart 實作 code 改寫為敘述（§4.4、§5.1、§5.4、§5.6、§6.3、§6.4、§7.2、§7.3、§12）。保留 code 的例外：顏色、Firestore Rules、部署指令、設定檔、ASCII 圖、schema tree。詳見 MEMORY.md。

---

## 歷史（> 7 天）

_（之後超過 7 天的條目搬到這裡，或刪掉——git log 留得住）_
