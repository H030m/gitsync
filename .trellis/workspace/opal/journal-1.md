# Journal - opal (Part 1)

> AI development session journal
> Started: 2026-06-02

---



## Session 1: Trellis team setup + implement addRepo callable

**Date**: 2026-06-02
**Task**: Trellis team setup + implement addRepo callable
**Branch**: `feature/add-repo-callable`

### Summary

Set up Trellis for team use (developer identity, develop-based git-flow convention in spec + docs). Implemented addRepo Cloud Function (URL parse, GitHub access verify, best-effort webhook registration, atomic 3-doc write under apps/gitsync/) with the project's first backend test suite (jest+ts-jest, 13 tests). Recorded course constraint: Final Demo limited to Flutter+Firebase; Cloud Functions confirmed allowed.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0012694` | (see git log) |
| `d8b69eb` | (see git log) |
| `147f1e7` | (see git log) |
| `7396fbf` | (see git log) |
| `582a706` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: GitHub OAuth finishing + first live deploy (addRepo/OAuth e2e)

**Date**: 2026-06-02
**Task**: GitHub OAuth finishing + first live deploy (addRepo/OAuth e2e)
**Branch**: `feature/github-oauth`

### Summary

Finished GitHub OAuth (module E): fixed createdAt-reset bug via transaction, added kIsWeb signInWithPopup web path, auth_vm unit tests (hand-rolled fake, no new deps), cleaned E-module TODO, enhanced SETUP B.4. Upgraded local Flutter to 3.44.1. Then deployed addRepo + githubWebhook to gitsync-645b3 and verified end-to-end: live GitHub OAuth login + add repo both work. Recorded the three first-deploy gotchas (secret prompt, build SA permission, Cloud Run allow-unauthenticated) in SETUP and MEMORY.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0cdc8e0` | (see git log) |
| `730466e` | (see git log) |
| `fac85fd` | (see git log) |
| `7ddc050` | (see git log) |
| `11feff3` | (see git log) |
| `eb23e81` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: Implement removeRepo (backend + delete UI)

**Date**: 2026-06-02
**Task**: Implement removeRepo (backend + delete UI)
**Branch**: `feature/remove-repo`

### Summary

Implemented removeRepo callable (owner check, best-effort deleteWebhook, member-pointer cleanup + recursiveDelete of repo + subcollections) with 7 unit tests. Added minimal delete UI: RepoListViewModel.removeRepo + per-row delete button with confirm dialog, list auto-updates via stream. Captured recursiveDelete cleanup-ordering in backend spec. All lint/typecheck/tests green.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ee9dc29` | (see git log) |
| `070bbf8` | (see git log) |
| `aeb980a` | (see git log) |
| `4e99e38` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: breakdownTaskFlow Step 1-6 + add_todo spec input

**Date**: 2026-06-02
**Task**: breakdownTaskFlow Step 1-6 + add_todo spec input
**Branch**: `feature/breakdown-flow`

### Summary

Implemented breakdownTaskFlow (context from pasted SPEC.md + repo info -> OpenAI structured output -> detectCycles+re-prompt -> pre-gen taskIds -> index->taskId translation -> batch write tasks as source:ai_breakdown; flow does not touch isBreakingDown, handler owns lock). Shallow-graph prompt (~5-12 top-level TODOs). Fixed add_todo setState button bug + enlarged spec paste box + mounted guard. Boundary-mocked test suite (32 green). Specs: handler/flow lock-ownership division, OpenAI .beta.parse SDK-path convention. Deployed + live-verified: TODOs generate with dependsOn populated. Next: render dependency graph in TasksBoard Graph tab (currently stub).

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `329735f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: Task dependency graph in TasksBoard Graph tab

**Date**: 2026-06-02
**Task**: Task dependency graph in TasksBoard Graph tab
**Branch**: `feature/task-graph-view`

### Summary

Replaced the Graph-tab stub in TasksBoardPage with TaskGraphTab: renders a dependency DAG from vm.tasks using the graphview package (1.5.1) + Sugiyama top-down layout in an InteractiveViewer. Nodes = tasks (status-colored cards, tap -> goTaskDetails), edges = prerequisite->dependent, dangling edges skipped, isolated nodes shown, empty-state placeholder. Added graphview dep (user-approved). Spec: graphview/DAG convention (use plain GraphView + own InteractiveViewer not GraphView.builder; addNode every node; Node.Id key round-trip). Live-verified by user (flutter run). analyze clean, 7 tests green.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `6b31529` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: GitHub sync: webhook ingestion + task/issue/PR triggers

**Date**: 2026-06-02
**Task**: GitHub sync: webhook ingestion + task/issue/PR triggers
**Branch**: `feature/github-webhook`

### Summary

End-to-end GitHub integration. Webhook (HMAC verify on rawBody + idempotency + dispatch -> raw writes to commits/pullRequests/issues) + githubClient.createIssue. Triggers: onTaskCreated mirrors task->GitHub issue (stores githubIssueNumber), onCommitCreated parses #N->linkedTaskIds + embedding + aiSummary (Rule D), onPRMerged (onDocumentWritten, parses closing refs -> txn mark done + counters), onIssueWritten (new, reverse-sync). tools/issueRefs + taskStatus. Linking via issue-mirror (#N). Check caught a production bug: onPRMerged was onDocumentUpdated but the PR doc is created already merged -> never fired; fixed to onDocumentWritten + spec Rule E. 8 suites / 65 tests green. Deployed 2026-06-02 (githubWebhook public-access opened on Cloud Run); onTaskCreated live-verified end-to-end. Remaining triggers (onCommitCreated / onPRMerged / onIssueWritten) deployed but not yet live-tested.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `c19231d` | (see git log) |

### Testing

- [OK] Unit: 8 suites / 65 tests green (boundary-mocked).
- [OK] Live (2026-06-02): deployed githubWebhook + 4 triggers; opened public invoker on `githubwebhook` Cloud Run service. **onTaskCreated** verified end-to-end — creating a new task auto-creates a GitHub issue and writes `githubIssueNumber` back to the task doc.
- [OK] Live (2026-06-02): onCommitCreated (#N link + aiSummary), onPRMerged (closes #N -> task done + counters), onIssueWritten (close/reopen reverse-sync) — all verified end-to-end.

### Status

[OK] **Completed** — code + full live verification (githubWebhook + all 4 triggers). Merged develop -> main.

### Next Steps

- Next feature: #3 assignTaskFlow (module D dynamic task assignment).


## Session 7: assignTaskFlow — agentic dynamic task assignment

**Date**: 2026-06-02
**Task**: assignTaskFlow — agentic dynamic task assignment
**Branch**: `feature/assign-task-flow`

### Summary

Implemented assignTaskFlow: OpenAI function-calling agentic loop (max 5 rounds, 4 tools: readTeamState=members+users join, searchMemberCommits=findNearest repoId+author.login prefilter, getTaskDependents, finalizeAssignment) picks best assignee by load/expertise/commit-history/dependents. Auto-apply: writes tasks/{taskId}.assigneeId + rebalances activeIssueCount in a transaction (reassign old-1/new+1, atomic). Pre-checks (task-done/no-member throw, single-member shortcut skips OpenAI) + lowest-load fallback. trellis-check caught a latent prod bug in the already-shipped handlePush: commit author handle persisted as author.username but schema+consumer use author.login -> vector search silently returned []; fixed + captured as database-guidelines Rule F. Discord-chat RAG deferred to future TODO (readTeamState already returns discordUserId for it). 9 suites/73 tests green. Not yet deployed; needs new commits vector index.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `7533790` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 8: onTaskUpdated — auto-assign downstream on done + FCM notify

**Date**: 2026-06-02
**Task**: onTaskUpdated — auto-assign downstream on done + FCM notify
**Branch**: `feature/auto-assign-on-done`

### Summary

Implemented the onTaskUpdated trigger (was a stub): on a task's status transition to done, query downstream tasks (dependsOn array-contains), keep only those whose every prerequisite is now done (ready filter, in-code), auto-assign the unassigned ones by reusing assignTaskFlow (auto-apply owns its counters — trigger touches no counters), and FCM-notify each newly-ready task's assignee (new tools/notify.ts, reads users/{uid}.fcmToken, best-effort). Transition guard (before!=done && after==done) prevents recursion when assignTaskFlow writes downstream assigneeId. Per-downstream try/catch = best-effort. onTaskUpdated now declares secrets:[openaiKey] + timeoutSeconds 300. trellis-check passed clean (0 issues): recursion trace, no double-counting, ready filter, data-flow (fcmToken written by Flutter user_repo), best-effort all verified. Added database-guidelines Rule G (single array-contains + in-code filter over manual composite index). 10 suites/84 tests green. Not yet deployed/live-tested.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `dfa13f9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 9: addRepo join-as-member on duplicate

**Date**: 2026-06-02
**Task**: addRepo join-as-member on duplicate
**Branch**: `feature/add-repo-join-member`

### Summary

Fixed addRepo rejecting a second collaborator with already-exists. Now: permission check (push/admin via verifyRepoAccess) runs before a create-vs-join split. New repo -> owner + webhook + 3 docs (unchanged). Existing repo -> join path (skips webhook): if already a member, idempotent {repoId, alreadyMember:true} no writes; else batch set members/{uid} role member + users/{uid}/repos/{repoId} + repos/{repoId}.memberIds arrayUnion(uid), never overwriting webhookSecret/createdBy. Non-collaborator still rejected. Frontend unchanged (repo-list stream reads repos.where memberIds array-contains uid, which the join writes). trellis-check 0 issues; noted firestore.rules is still the DEFAULT OPEN ruleset (allow read/write until 2026-06-25) — security follow-up, out of scope here. 10 suites/86 tests green.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `041d19d` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 10: Fix: dynamic assignment hard-failed on missing commits vector index

**Date**: 2026-06-03
**Task**: Fix: dynamic assignment hard-failed on missing commits vector index
**Branch**: `feature/assign-commit-search-resilient`

### Summary

Live debug: onTaskUpdated auto-assignment left downstream assigneeId null. Logs showed assignTaskFlow ran the agentic loop but searchMemberCommits findNearest threw 9 FAILED_PRECONDITION (missing vector index) which propagated and killed the whole assignment. Root causes: (1) optional commit-search signal was not best-effort — one throw aborted the flow; (2) firestore.indexes.json declared the commits vector indexes COLLECTION_GROUP but the query is .collection() = COLLECTION scope, so even deploying built the wrong index. Fix: wrap embed+findNearest+map in try/catch -> return [] + warn (assignment now finalizes on workload/expertise/dependents even with no index and no commits — demo no longer needs the index); changed both commits vector indexes to queryScope COLLECTION; left discordMessages COLLECTION_GROUP (no findNearest consumer). Confirmed user's remove/re-add/regenerate test flow was NOT the cause. Extended error-handling spec: optional/secondary signal tools must be best-effort + must not hard-depend on a user-deployed index + match index queryScope to query. trellis-check 0 issues; 12 suites/98 tests green. User to redeploy functions:onTaskUpdated,assignTask; index deploy optional now.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `aae8c7e` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 11: push 自動判定 task 完成並設為 done（AI judge + onCommitCompletesTask trigger）

**Date**: 2026-06-14
**Task**: push 自動判定 task 完成並設為 done（AI judge + onCommitCompletesTask trigger）
**Branch**: `feature/push-auto-complete-task`

### Summary

新增 onCommitCompletesTask trigger：commit 推到預設分支且含 #N 時，由 LLM (judgeTaskCompletion) 判斷對應 task 是否完成，confidence>=0.8 則 markTaskDone。handlePush 以獨立 set(merge) 標記 onDefaultBranch 解決 first-seen/idempotency 限制。check 階段修掉 markIdempotent 搶 key 餓死 onCommitCreated 的 bug（guard 須排在 markIdempotent 前），spec 已記錄。377 tests 全綠。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `4cc9a57` | (see git log) |
| `2769a52` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 12: agentic 增量式 task 拆解(grounded in existing tasks + repo 記憶隔離)

**Date**: 2026-06-15
**Task**: agentic 增量式 task 拆解(grounded in existing tasks + repo 記憶隔離)
**Branch**: `feature/incremental-breakdown`

### Summary

breakdownTask 改成資料狀態自動分流:repo 有 task → 多輪 function-calling loop,模型用 repo-scoped 分頁工具(listExistingTaskTitles/searchExistingTasks)+ searchPastCommits/readRepoPlanningDocs grounding 按需查詢,只補缺漏、context 不隨任務數成長、去重 by construction;新任務可依賴既有 taskId,cycle 檢查跨既有+新混合圖;empty repo 維持原單發拆解。check 修掉 dangling tool_call(同輪 read+submit 漏回覆 → 真實 OpenAI 400)的 live-only bug,並把這條通用 agentic 陷阱寫回 error-handling spec。391 tests 全綠。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `eb3707d` | (see git log) |
| `ff730d8` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 13: 增量拆解 prompt 對齊 baseSystem + W6 多語

**Date**: 2026-06-15
**Task**: 增量拆解 prompt 對齊 baseSystem + W6 多語
**Branch**: `feature/align-incremental-prompt`

### Summary

incrementalBreakdownSystem 由獨立 const 改為 incrementalBreakdownSystem(language)=buildSystemPrompt({agentBody,language}),對齊 main 的共用 prompt 架構;language 從 handler→breakdownTaskFlow→incrementalBreakdown→prompt 全程貫通。無演算法變更,no-arg byte-stable,增量語意(工具探索不 dump、真實 taskId、混合圖 DAG、submit 一次)保留。399 tests 綠。順手還原被 flutterfire 誤刪 macos/windows + 壓平的 firebase.json。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `259d42f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 14: 增量拆解可觀測性:記錄 agent 工具調用與依賴統計

**Date**: 2026-06-15
**Task**: 增量拆解可觀測性:記錄 agent 工具調用與依賴統計
**Branch**: `feature/incremental-breakdown-observability`

### Summary

incrementalBreakdown 加結構化 log:每輪每個 tool call 記 {round,tool,args摘要,resultCount};submit 記 {subtaskCount,totalDependsOnNew,totalDependsOnExisting};listExistingTaskTitles/searchExistingTasks 成功也記 count。純 log、best-effort、演算法與 model-visible 內容不變。403 tests 綠。目的:診斷增量拆解新任務沒連既有任務依賴是『沒查』還是『查了不連』。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `3dd960b` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 15: 每日彙整:合併 Discord+摘要為單一視圖、精簡卡片、全頁 AI 中文

**Date**: 2026-06-15
**Task**: 每日彙整:合併 Discord+摘要為單一視圖、精簡卡片、全頁 AI 中文
**Branch**: `feature/merge-daily-digest`

### Summary

Daily 頁把 Summary/Discord 兩分頁合成單一每日視圖(每天:摘要+重點(含blockers)+Discord摘要),移除提交彙總/貢獻卡與參考訊息、改用單一 Ask GitSync 聊天。全頁 AI 輸出強制中文:askRepo 端到端加 W6 language(Flutter→callable→flow→buildSystemPrompt),discordDailyDigest prompt 改繁中、偏平鋪 bullet。順手修 repo_list_vm_test 的 FunctionsService interface drift。flutter 99 / functions 403 全綠。亮暗色皆用 colorScheme token。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `bf02f40` | (see git log) |
| `0e98350` | (see git log) |
| `a5e8038` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 16: 每日彙整精簡:移除 count chip/鎖/AI調整/locked + 修 digest 初始範圍

**Date**: 2026-06-15
**Task**: 每日彙整精簡:移除 count chip/鎖/AI調整/locked + 修 digest 初始範圍
**Branch**: `feature/remove-daily-chips-lock`

### Summary

移除日報 count chip 與 Discord digest 鎖 UI;整個移除 locked(digest 凍結)+ editDiscordDigest(AI 調整)功能,跨 functions(刪 setDigestLock/editDiscordDigest/botEditDigest + flow 的 locked 防護)、Flutter(model/VM/service/UI)、discord-bot(/gitsync-digest 指令)三套件,digest 改為永遠重生。修 Discord 摘要初始載入不顯示的 bug:didChangeDependencies 用 post-frame setViewRange 把 discord 視窗對齊日報範圍(display-only 不寫 Firestore)。functions 416 / flutter 104 / bot tsc 全綠。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `91a7968` | (see git log) |
| `6f130cd` | (see git log) |
| `e550e92` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 17: Android GitHub token 取得/刷新(web-auth + exchangeGitHubCode CF)

**Date**: 2026-06-16
**Task**: Android GitHub token 取得/刷新(web-auth + exchangeGitHubCode CF)
**Branch**: `feature/android-github-token`

### Summary

firebase_auth 在 Android 拿不到 GitHub provider token,改用次要 OAuth:flutter_web_auth_2 取 code → 新 CF exchangeGitHubCode 以 defineSecret 的 client_secret 換 gho_ token 寫回 users/{uid}.githubAccessToken(回 {ok:true} 不回 token、CSRF state 驗證)。getCommitGraph 把 GitHub 401 對映成 HttpsError('failed-precondition','github-token-invalid: ...'),app 偵測後在 Settings/分支圖錯誤態顯示『重新連結 GitHub』CTA。client_secret 只在 CF;client_id 公開、寫進 app+functions config。owner 已建 OAuth App(callback gitsync://oauth/github)+設好 GITHUB_OAUTH_CLIENT_SECRET。functions 424 / flutter 108 綠。spec 記於 backend/error-handling。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `cd7ce53` | (see git log) |
| `8db09aa` | (see git log) |
| `9eacd26` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 18: Daily 範圍全空空狀態 + 空白天收合一行

**Date**: 2026-06-16
**Task**: Daily 範圍全空空狀態 + 空白天收合一行
**Branch**: `develop`

### Summary

Daily 頁:範圍內全空 → 單一置中空狀態(含『調整日期範圍』開 picker,復用共用 helper);混合範圍裡的空白天(無 report 無 digest)收成精簡一行『無活動』,點開才露出『產生報告』。純 UI、亮暗色 colorScheme。合進大幅演進過的 develop(token CTA/stats overhaul 等)為乾淨 auto-merge,analyze 乾淨、119 tests 綠。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `198869f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
