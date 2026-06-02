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
- [ ] Live (pending): onCommitCreated (#N link + aiSummary), onPRMerged (closes #N -> task done + counters), onIssueWritten (close/reopen reverse-sync).

### Status

[OK] **Completed** (code). Live-test in progress: onTaskCreated passed; PR/commit/issue triggers still to verify.

### Next Steps

- Finish live-testing the remaining 3 triggers, then merge develop -> main.
