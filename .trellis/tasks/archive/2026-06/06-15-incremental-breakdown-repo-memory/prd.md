# 增量式 task 拆解:第二次拆解參考既有任務 + repo 記憶隔離

## Goal

讓 `breakdownTask` 在 repo 已有任務時,做「增量拆解」:參考既有 task(避免產生重複、且新任務可依賴既有任務),而不是像現在這樣每次都從 SPEC 重拆、盲目寫一批可能重複的任務。同時確保所有相關記憶嚴格 **repo 隔離**。

## What I already know(已從程式碼確認)

* `breakdownTaskFlow`(`functions/src/flows/breakdownTask.ts`)目前:
  * context 來源僅 `projectBrief` + `repoDocs` + repo name/desc,**完全不讀 `tasks` 集合**(第 71 行還寫死「no existing tasks yet」)。
  * `dependsOn` 是「同批回應內」的 0-based index,**無法指向既有 taskId**。
  * Step 6 直接 `batch.set` 一批新 task,**不去重**。
  * prompt(`prompts/breakdownTask.ts`)定位為「新匯入專案的首次淺層拆解,5–12 個 top-level TODO」。
* 觸發點:`lib/views/tasks/add_todo_page.dart:84` `fn.breakdownTask(repoId, goal)`,**沒有**「只在無 task 時」的限制;flow 自己寫 Firestore。
* handler 有 `isBreakingDown` 分散式鎖防併發(`handlers/breakdownTask.ts`)。
* 記憶隔離現況:`meta/projectBrief`、`meta/repoDocsCache`、`commits/*`、`discordDigests/*`、`tasks/*` **皆 repo-scoped**;**唯一例外 `users/{userId}.expertiseTags` 為跨 repo 共用**(`tools/assignTools.ts`)。

## Assumptions (temporary)

* 增量模式採「自動偵測」:repo 已有 task → 走增量 prompt;無 task → 維持現有首次拆解。app 端不需新按鈕。
* 新任務的去重 + 依賴既有任務,需擴充 LLM 的 schema(既有 task 以穩定參照傳入,dependsOn 可指既有 taskId)。

## Decisions(已與 user 確認)

* **D1 進入方式 = 自動偵測**:flow 先讀 `repos/{repoId}/tasks`;非空 → 增量 prompt(參考既有、去重、可依賴);空 → 維持現有首次拆解。app 端不改。
* **D2 隔離範圍**:成員專長記憶(`users/{uid}.expertiseTags`)**刻意維持跨 repo 共用,不動**。本 task 的「記憶隔離」指任務/拆解層——既有 task 讀寫一律 `repos/{repoId}/tasks`,天然 repo 隔離;需在實作與測試中確保不跨 repo 讀取。

* **D3 去重 = 靠 prompt(MVP)**:在 agentic 系統 prompt 明訂「只補缺漏、勿重複既有任務」;模型透過工具查既有 task 做判斷。不做確定性相似度過濾(未來增強)。
* **D4 既有 task 欄位 = title + status + dependsOn**:工具回傳這些;足夠去重 + 接進既有 DAG;不回 description(省 token)。
* **D5 規模策略 = 全 agentic 工具化**:**不 dump 任何 task 清單進 prompt**;既有 task 改由模型按需用工具查詢(同 askRepo / assignTask pattern)。context 與專案大小脫鉤。

## Technical Approach

breakdown 從「單發 `beta.chat.completions.parse` structured output」改寫成 **多輪 function-calling agentic loop**(比照 `flows/assignTask.ts` / `flows/askRepo.ts`)。

1. **自動分流**(D1):
   - repo 無 task → 維持**現有單發首次拆解**(不動、低風險)。
   - repo 有 task → 走**新的 agentic 增量拆解**。
2. **工具集**(全部 repo-scoped,分頁/限量,絕不一次全倒)。流程是「先探索現況 → 再生成缺漏」,去重 by construction:
   - **查既有 task**(只回 `{taskId,title,status,dependsOn}`):
     - `listExistingTaskTitles({status?, cursor?})` — 分頁總覽,讓模型先掌握輪廓。
     - `searchExistingTasks({query, limit?})` — 關鍵字搜尋相關 task(MVP 關鍵字;embedding 語意搜尋列未來)。
   - **現實對照(grounding,讓生成貼近專案真實狀態,而非只看可能過時的 task 清單)**:
     - `searchPastCommits({query, limit?})` — 向量搜尋實際 commit,抓「task 沒標完成但其實已做」的落差(沿用既有工具)。
     - `readRepoPlanningDocs()` — repo 內 `.trellis`/`CLAUDE.md`/`docs` 計畫與架構(沿用既有工具)。
     - project brief 作為穩定 context 前綴(沿用 `readProjectBrief`/`formatBriefForPrompt`)。
3. **終結器工具** `submitBreakdown({subtasks})`,參數即子任務 schema(Zod 驗證):每個含 `title, description, estimatedHours, dependsOnNew:number[], dependsOnExisting:string[]`。
4. **dependsOn 還原**:`dependsOnNew`(同批 0-based index)+ `dependsOnExisting`(既有 taskId)→ 寫入時合併成最終 `dependsOn: string[]`。
5. **cycle 偵測擴充**:`detectCycles` 改成「既有 task(含既有 dependsOn)+ 新 task」混合圖檢查;偵測到環 → re-prompt 一次;兩次仍有環 → 報錯。
6. **round 控制**:比照其他 flow 設 MAX_ROUNDS(~5)+ hard ceiling;跑完未 submit → 報錯(不靜默寫入)。
7. **隔離**:所有工具只走 `apps/gitsync/repos/{repoId}/...`;測試證明工具不讀到別 repo 的 task。
8. **不動** `users/{uid}.expertiseTags`(D2)。沿用 handler 的 `isBreakingDown` 鎖。

## Requirements (evolving)

* repo 已有 task 時,拆解需參考既有 task,避免產生語意重複的新任務。
* 新任務的 `dependsOn` 可指向**既有 taskId**(不只同批 index)。
* 所有讀寫嚴格 repo-scoped,記憶不跨 repo 外洩。

## Acceptance Criteria

* [ ] repo 無 task 時:行為與現在一致(首次拆解)。
* [ ] repo 有 task 時:走 agentic 增量模式,模型用工具查既有 task(不 dump 全清單),且明訂勿重複。
* [ ] context 不隨 task 數線性成長(工具分頁/限量,prompt 不含完整 task 清單)。
* [ ] 拆解 agent 可透過工具對照實際 commit/規劃文件(grounding),不只看 task 清單。
* [ ] 新任務的 `dependsOnExisting` 能正確還原成既有 taskId 寫入 `dependsOn`。
* [ ] 既有 + 新任務的混合依賴圖為 DAG;偵測到環會 re-prompt;兩次仍有環則報錯。
* [ ] 跑完 round 未 submit → 報錯,不靜默寫入。
* [ ] 工具讀取嚴格 repo-scoped:測試證明不會讀到別 repo 的 task。

## Definition of Done

* 單元測試(增量 prompt 組裝、dependsOn 解析既有 taskId、去重、cycle 偵測跨既有+新任務)
* Lint / typecheck 綠燈
* 行為變更寫回 spec

## Out of Scope (explicit)

* 遞迴深層拆解(維持淺層)
* UI 大改(除非 Q1 決定要新入口)

## Technical Notes

* 對照:現有 `detectCycles` 只處理同批 index,需擴充成「既有 taskId + 新 index」混合圖。
* 既有 task 讀取:`repos/{repoId}/tasks`(title/status/description/dependsOn)。
* 隔離基準:所有路徑均為 `apps/gitsync/repos/{repoId}/...`。
