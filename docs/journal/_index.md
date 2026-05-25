# 團隊近 7 天動態 (Index)

> 這份檔案由每位 AI / 人在寫完日誌後**自行更新**。最新動態在最上面，超過 7 天的條目自動下移到「歷史」區塊（或直接刪除——repo 有 git 紀錄）。
>
> 開工前必讀。看到「進行中」欄裡有別人正在動的檔案，請避開或先協調。

---

## 進行中（aka 不要碰）

| 隊員 | 在做什麼 | 預計動的檔案 |
|---|---|---|
| (空) | — | — |

---

## 2026-05-26（今天）

- 初始化專案文件結構，建立 `docs/journal/` 與五人 journal 初始檔。
- 架構師 review pass：併發守則 (§4.4)、排程扇出 (§5.4)、commit filter (§5.6)、Discord 簡化為「訊息直寫 Firestore」(§7) — 全數寫入 ARCHITECTURE.md + MEMORY.md。
- 第二輪 review：補強 §4.4 Rule C（trigger at-least-once → in-trigger idempotency 強制）、§7 forwarder + ingest 雙層 Discord 訊息過濾、§10 Sprint 4 與簡化版 Discord 對齊。
- 第三輪 review：§5.1 breakdownTask 分散式鎖（isBreakingDown + 兜底排程）、§6.3 ↔ §4.3 職責切分（webhook 只寫 raw，trigger 才做 AI）、§7.2 forwarder 指數退避 retry、§11 風險表全面更新。
- 第四輪 review（docs/issue.txt）：§5.1 補 Step 4-6 索引→taskId 翻譯、§5.6 補 tasks.dependsOn array-contains 複合索引、§2.1 users 加 discordUserId 欄位、§5.2/§5.3 tool 餵 AI 三組身份對照。
- 文體規範：ARCHITECTURE.md 內所有 TS/Dart 實作 code 改寫為敘述（§4.4、§5.1、§5.4、§5.6、§6.3、§6.4、§7.2、§7.3、§12）。保留 code 的例外：顏色、Firestore Rules、部署指令、設定檔、ASCII 圖、schema tree。詳見 MEMORY.md。

---

## 歷史（> 7 天）

_（之後超過 7 天的條目搬到這裡，或刪掉——git log 留得住）_
