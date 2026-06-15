# feat(assign): give the assign agent access to a member's completed task titles

## Goal

Fix a real-world miss reported by the user: brand-new repo, Ryan finished
5 typing tasks, Alan has 0; both at `activeIssueCount: 0`. A new typing
task came in, the agent assigned it to Alan. Because the assign flow's
signals are `activeIssueCount`, `expertiseTags`, and a
`searchMemberCommits` semantic search over the **commits** collection,
it had no way to see that Ryan had done five related tasks — there were
no commits to search.

Add a tool that lets the agent read a member's recently-completed
**tasks** (by title) and **judge relevance itself**, rather than asking
the caller to pass an exact-match query.

## Root cause (diagnosed 2026-06-16)

`functions/src/flows/assignTask.ts` tools today:

* `readTeamState(repoId)` → `{userId, name, githubLogin, discordUserId,
  activeIssueCount, expertiseTags, lastActiveAt}`. **No
  `completedTaskCount`, no past-task list.**
* `searchMemberCommits(memberId, query)` → vector search over the
  commits collection (not tasks).
* `getTaskDependents(taskId)` → who's blocked.
* `finalizeAssignment()` → write.

System prompt (`functions/src/prompts/assignTask.ts:12–13`):

> *"Prefer members with lower activeIssueCount"*
> *"Prefer members whose expertiseTags / recent commits match the task
> topic"*

In a fresh repo with no commits yet, the "recent commits" signal is
empty and every workload-tied candidate looks identical.

## Decisions (locked 2026-06-16)

* **New tool**: `listMemberCompletedTasks(memberId, limit?)`.
  * Returns `Array<{taskId: string, title: string, completedAt: string |
    null}>` — the member's most recently completed tasks, newest first.
  * Default `limit = 20`, hard max `50`.
  * Filters Firestore `tasks` by `assigneeId == memberId AND status ==
    'done'`, orders by `updatedAt desc`, takes the first `limit`.
* **No new tool for "count related"**. Letting the agent eyeball
  titles is the user's stated preference and avoids us having to
  re-derive a similarity metric server-side. The agent already does
  semantic reasoning at the LLM layer; titles are short.
* **No change to `readTeamState`'s return shape.** Adding the
  completed list there would bloat every roster snapshot the agent
  reads. Drilling-down per top candidate is cheaper.
* **Prompt updated** to teach the agent the new pattern:
  1. Read roster + workload via `readTeamState`.
  2. For the top workload-tied candidates, call
     `listMemberCompletedTasks(userId)` and **judge** whether the past
     titles indicate experience related to the new task — semantic
     match, not keyword match. The user's example: "typing"
     experience may live under titles like "type out chapter 3" or
     "ten-minute speed drill", which the agent should recognise as
     related.
  3. Prefer the member with more **related** completed tasks among
     ties; the existing workload + expertise + commit-relevance
     signals still rank everything else.
* **Index check**: the new query is two `where` clauses on the same
  collection (`assigneeId`, `status`) + `orderBy('updatedAt')`. This
  needs a composite index. Add it to `firestore.indexes.json` so the
  query doesn't 9-FAILED_PRECONDITION on first call.

## Requirements

* Add `listMemberCompletedTasks(repoId, memberId, limit?)` to
  `functions/src/tools/assignTools.ts`. Best-effort: returns `[]` if
  the query throws (mirrors `searchMemberCommits`'s degrade-to-empty
  contract).
* Register the tool in `functions/src/flows/assignTask.ts`:
  * Add to the tool-list registered with OpenAI (with a clear
    description).
  * Add to the `runTool` dispatch switch.
* Update the assign agent's system prompt
  (`functions/src/prompts/assignTask.ts`) to mention the new tool +
  the relevance-judgment pattern. Keep the existing rules; only
  extend.
* Add the composite index
  (`apps/gitsync/repos/{repoId}/tasks` with `assigneeId ASC, status
  ASC, updatedAt DESC`) to `firestore.indexes.json`.
* Tests: extend the existing assign flow test in
  `functions/src/__tests__/assignTask.test.ts` to cover at least one
  case where two candidates are workload-tied and the one with more
  related completed-task titles wins. Mirror the existing test's
  mocking pattern.

## Acceptance Criteria

* [ ] `cd functions && npm run typecheck` clean.
* [ ] `cd functions && npm run lint` clean.
* [ ] `cd functions && npm test` — full suite green (was 41 / 416 green).
* [ ] At least one new test asserts the assign agent picks the candidate
      with relevant completed-task history when workload is tied.
* [ ] `firestore.indexes.json` has the new composite index on
      `apps/gitsync/repos/{repoId}/tasks`.
* [ ] Smoke (deferred): brand-new repo, give one member 2-3 done tasks
      with titles that semantically match a new task's topic; assign
      the new task; the relevant member is picked.

## Definition of Done

* AC items pass.
* Single commit on develop.
* `flutter analyze` skipped (project memory; not relevant here).

## Out of Scope

* Promoting `completedTaskCount` directly into `readTeamState` —
  decided against (would bloat every snapshot).
* Server-side semantic similarity ranking of completed tasks (a
  per-title embedding compare). Let the LLM do it; titles are short
  and the workload-tied set is tiny.
* Updating the kanban or any frontend UI to show "relevance" or
  "recommendation reasoning". The reasoning string already returned by
  `assignTask` covers it.
* Modifying `searchMemberCommits` or commits ingest. The new tool is
  additive.
* PR triage / reviewer recommendation. Unrelated flow.

## Technical Notes

* `tasks/{taskId}.assigneeId` and `tasks/{taskId}.status` are the
  canonical filter fields per the existing assign flow code. No
  schema change needed.
* `updatedAt` is set by `onPRMerged` / status writes; for "completed
  recently" it's the right ordering field. If `completedAt` doesn't
  exist on docs, the `orderBy('updatedAt')` still works.
* Per-member limit of 20 strikes a balance: enough titles for the
  agent to judge, not so many that prompt context bloats. Hard
  cap 50 prevents abuse.
* The new tool is best-effort: a Firestore error returns `[]`. The
  agent then has the existing `searchMemberCommits` + workload
  signals to fall back on — same degraded-graceful pattern as the
  rest of the assign flow.
