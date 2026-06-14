# 增量拆解 prompt 對齊 baseSystem + W6 多語

## Goal

把 `incrementalBreakdownSystem`(develop-only、在 06-15 增量拆解功能引入的獨立常數 prompt)對齊 main 帶進來的共用 prompt 架構:走 `buildSystemPrompt`(prompts/baseSystem.ts)+ 支援 W6 `language`,讓增量拆解 agent 跟其他所有 agent 一致。

## Background / What I already know

* main 的 agent-quality 批次把每個 agent 的 system prompt 改成 `buildSystemPrompt({ agentBody, language })`(`prompts/baseSystem.ts`):`GITSYNC_BASE_SYSTEM`(共用 identity / grounding / 語言 / tool 語意)+ 各 flow 的 `agentBody`,並以 `language?` 強制輸出語言(W6)。
* 標準範例:`generateHandoffSystemPrompt(language?) = buildSystemPrompt({ agentBody, language })`(`prompts/generateHandoff.ts:43`);`breakdownTaskSystem(language?)` 首次拆解也已是這形式。
* 現況落差(`prompts/breakdownTask.ts`):
  * `incrementalBreakdownSystem` 是**獨立 const 字串**,沒走 `buildSystemPrompt`、不吃 `language`。
  * `flows/breakdownTask.ts` 的 `incrementalBreakdown(repoId, goal)` 沒接 `language`;`breakdownTaskFlow` entry 已有 `language`(目前只傳給 `firstPassBreakdown`)。
* W6 `language` 一路從 handler(`handlers/breakdownTask.ts`)傳進 `breakdownTaskFlow`,只差沒接到增量路徑。

## Requirements

* `incrementalBreakdownSystem` 改成 `incrementalBreakdownSystem(language?: string)`,回 `buildSystemPrompt({ agentBody: <incremental rules body>, language })`。
* `agentBody` 只保留增量專屬規則(workflow:explore→ground→generate、去重、dependsOnNew/Existing、DAG、shallow…);與 `GITSYNC_BASE_SYSTEM` 重複的泛用 identity/grounding/語言敘述可精簡(避免重複),但**不可弱化**增量專屬語意(尤其「不 dump、用工具探索」「dependsOnExisting 用真實 taskId」)。
* `incrementalBreakdown(repoId, goal, language?)` 接收並把 `language` 傳給 `incrementalBreakdownSystem(language)`。
* `breakdownTaskFlow` 把既有的 `language` 也傳進 `incrementalBreakdown(...)`。

## Acceptance Criteria

* [ ] 增量拆解的 system prompt 經由 `buildSystemPrompt`(含 `GITSYNC_BASE_SYSTEM` 前綴)。
* [ ] 帶 `language` 時,增量拆解的 system prompt 含該語言強制指示;不帶時與基準一致(byte-stable、快取友善)。
* [ ] `language` 從 handler → flow → incrementalBreakdown → prompt 全程貫通。
* [ ] 不 dump task 清單、工具探索、dependsOn 兩欄、DAG 等既有行為與測試**不退步**(D5 等仍成立)。
* [ ] build / lint / 既有 functions 測試全綠;新增測試覆蓋「language 有/無」兩種 system prompt 差異。

## Definition of Done

* 單元測試(language 有無、prompt 經 buildSystemPrompt)
* Lint / typecheck / 既有測試綠燈
* 行為變更(若有)記回 spec

## Out of Scope

* 增量拆解的功能邏輯(探索/去重/DAG/cycle)——只動 prompt 組裝與 language 貫通,不改演算法。
* 其他 flow(都已對齊)。
* embedding 語意搜尋(仍是先前列的未來增強)。

## Technical Notes

* 動到的檔:`functions/src/prompts/breakdownTask.ts`(const→function + 抽 agentBody)、`functions/src/flows/breakdownTask.ts`(`incrementalBreakdown` 簽章 + 呼叫端傳 language)。
* 參照:`prompts/generateHandoff.ts:43`、`prompts/breakdownTask.ts:31`(breakdownTaskSystem)、`prompts/baseSystem.ts:62`(buildSystemPrompt)。
* 風險低:純 prompt 組裝 + 參數貫通,無資料/演算法變更。
