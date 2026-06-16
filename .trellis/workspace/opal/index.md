# Workspace Index - opal

> Journal tracking for AI development sessions.

---

## Current Status

<!-- @@@auto:current-status -->
- **Active File**: `journal-1.md`
- **Total Sessions**: 19
- **Last Active**: 2026-06-16
<!-- @@@/auto:current-status -->

---

## Active Documents

<!-- @@@auto:active-documents -->
| File | Lines | Status |
|------|-------|--------|
| `journal-1.md` | ~656 | Active |
<!-- @@@/auto:active-documents -->

---

## Session History

<!-- @@@auto:session-history -->
| # | Date | Title | Commits | Branch |
|---|------|-------|---------|--------|
| 19 | 2026-06-16 | 移除 Settings 頂端 Backend banner | `b3cf82f` | `feature/remove-settings-backend-banner` |
| 18 | 2026-06-16 | Daily 範圍全空空狀態 + 空白天收合一行 | `198869f` | `develop` |
| 17 | 2026-06-16 | Android GitHub token 取得/刷新(web-auth + exchangeGitHubCode CF) | `cd7ce53`, `8db09aa`, `9eacd26` | `feature/android-github-token` |
| 16 | 2026-06-15 | 每日彙整精簡:移除 count chip/鎖/AI調整/locked + 修 digest 初始範圍 | `91a7968`, `6f130cd`, `e550e92` | `feature/remove-daily-chips-lock` |
| 15 | 2026-06-15 | 每日彙整:合併 Discord+摘要為單一視圖、精簡卡片、全頁 AI 中文 | `bf02f40`, `0e98350`, `a5e8038` | `feature/merge-daily-digest` |
| 14 | 2026-06-15 | 增量拆解可觀測性:記錄 agent 工具調用與依賴統計 | `3dd960b` | `feature/incremental-breakdown-observability` |
| 13 | 2026-06-15 | 增量拆解 prompt 對齊 baseSystem + W6 多語 | `259d42f` | `feature/align-incremental-prompt` |
| 12 | 2026-06-15 | agentic 增量式 task 拆解(grounded in existing tasks + repo 記憶隔離) | `eb3707d`, `ff730d8` | `feature/incremental-breakdown` |
| 11 | 2026-06-14 | push 自動判定 task 完成並設為 done（AI judge + onCommitCompletesTask trigger） | `4cc9a57`, `2769a52` | `feature/push-auto-complete-task` |
| 10 | 2026-06-03 | Fix: dynamic assignment hard-failed on missing commits vector index | `aae8c7e` | `feature/assign-commit-search-resilient` |
| 9 | 2026-06-02 | addRepo join-as-member on duplicate | `041d19d` | `feature/add-repo-join-member` |
| 8 | 2026-06-02 | onTaskUpdated — auto-assign downstream on done + FCM notify | `dfa13f9` | `feature/auto-assign-on-done` |
| 7 | 2026-06-02 | assignTaskFlow — agentic dynamic task assignment | `7533790` | `feature/assign-task-flow` |
| 6 | 2026-06-02 | GitHub sync: webhook ingestion + task/issue/PR triggers | `c19231d` | `feature/github-webhook` |
| 5 | 2026-06-02 | Task dependency graph in TasksBoard Graph tab | `6b31529` | `feature/task-graph-view` |
| 4 | 2026-06-02 | breakdownTaskFlow Step 1-6 + add_todo spec input | `329735f` | `feature/breakdown-flow` |
| 3 | 2026-06-02 | Implement removeRepo (backend + delete UI) | `ee9dc29`, `070bbf8`, `aeb980a`, `4e99e38` | `feature/remove-repo` |
| 2 | 2026-06-02 | GitHub OAuth finishing + first live deploy (addRepo/OAuth e2e) | `0cdc8e0`, `730466e`, `fac85fd`, `7ddc050`, `11feff3`, `eb23e81` | `feature/github-oauth` |
| 1 | 2026-06-02 | Trellis team setup + implement addRepo callable | `0012694`, `d8b69eb`, `147f1e7`, `7396fbf`, `582a706` | `feature/add-repo-callable` |
<!-- @@@/auto:session-history -->

---

## Notes

- Sessions are appended to journal files
- New journal file created when current exceeds 2000 lines
- Use `add_session.py` to record sessions