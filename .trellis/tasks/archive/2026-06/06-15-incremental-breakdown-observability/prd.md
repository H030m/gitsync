# 增量拆解可觀測性:記錄 agent 每輪工具調用與探索結果

## Goal

讓 `incrementalBreakdown`(agentic 增量拆解)的執行**可從 Cloud Functions log 觀測**:每輪呼叫了哪些工具、參數重點、回傳幾筆,以及最後 submit 的依賴情況。目的是能診斷「為什麼新任務沒連到既有任務的依賴」——分辨出「agent 沒查既有 task」vs「查了但沒連依賴」。

## Background / 問題

* 現況 `incrementalBreakdown`(`functions/src/flows/breakdownTask.ts`)只 log:每輪輪次、cycle、round-limit、丟棄未知依賴。**不記每輪呼叫了哪個工具 / 參數 / 結果筆數**。
* `listExistingTaskTitles` / `searchExistingTasks`(`functions/src/tools/breakdownTools.ts`)**只在失敗時** `logger.warn`,成功不記。
* 結果:雲端 log 看不出 agent 到底有沒有呼叫 `listExistingTaskTitles` / `searchExistingTasks` 去探索既有任務 → 無法診斷依賴沒連上的原因。
* `breakdownTask` 也沒接 `agentTrace`(UI 即時軌跡)。

## Requirements

* **每輪工具調用 log**:在 `incrementalBreakdown` 的 tool dispatch,對每個 tool_call 記一筆結構化 log:`{ repoId, round, tool: <name>, args: <精簡摘要>, resultCount: <回傳筆數> }`(讀取類工具回陣列就記長度;`submitBreakdown` 記 `subtaskCount` + 依賴統計)。
* **工具成功路徑 log**:`listExistingTaskTitles` / `searchExistingTasks` 成功時也記回傳筆數(讓「有呼叫且回幾筆」可見)。
* **submit 依賴可見**:submit 時記 `{ subtaskCount, totalDependsOnNew, totalDependsOnExisting }`,直接看出有沒有連到既有任務。
* 不記敏感內容、不爆量:args 只記重點(query 字串、status、cursor 有無),結果只記**筆數**不記內容;沿用既有結構化 logger 慣例。
* best-effort:log 本身不可改變控制流、不可拋錯。

## Acceptance Criteria

* [ ] 重跑一次增量拆解後,雲端 log 能看出:每輪呼叫了哪些工具、`listExistingTaskTitles`/`searchExistingTasks` 是否被呼叫及回傳筆數。
* [ ] submit 那筆 log 能看出新任務對既有任務的依賴數(`totalDependsOnExisting`)。
* [ ] 不改變增量拆解的演算法 / 既有測試行為。
* [ ] build / lint / 既有 functions 測試全綠;新增測試斷言 dispatch 對讀取工具與 submit 有發出對應 log(可用 mock logger 斷言)。

## Definition of Done

* 單元測試(斷言關鍵 log 有被呼叫)
* Lint / typecheck / 既有測試綠燈
* 若 log 欄位約定值得記錄 → 寫回 logging-guidelines spec

## Out of Scope

* 把 `breakdownTask` 接上 `agentTrace`(UI 即時軌跡)——列為後續可選,本 task 只做 Cloud Functions log。
* 改 prompt / 演算法去「強迫」探索或連依賴(那是診斷後的下一步,先做可觀測性)。
* embedding 語意搜尋。

## Technical Notes

* dispatch 位置:`functions/src/flows/breakdownTask.ts`(tool_calls 迴圈 ~第 413、442、495 行;runTool switch ~599)。
* 工具:`functions/src/tools/breakdownTools.ts`(`listExistingTaskTitles:98`、`searchExistingTasks:141` 已有失敗 warn,補成功 info)。
* 參照 logger 慣例:`.trellis/spec/backend/logging-guidelines.md`;其他 agentic flow(assignTask)逐輪 log 的形式。
* 風險低:純加 log,無資料/演算法變更。
