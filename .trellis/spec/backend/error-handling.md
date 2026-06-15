# Error Handling (Cloud Functions)

> All functions use `firebase-functions/v2`. Source: [`ARCHITECTURE.md §4`](../../../docs/ARCHITECTURE.md),
> [`COURSE_METHODS.md §6`](../../../docs/COURSE_METHODS.md).

---

## Callables (`onCall`) — throw typed `HttpsError`

Check auth and validate args at the top; surface failures as `HttpsError` so the Flutter
client receives a typed `FirebaseFunctionsException`.

```ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';

export const breakdownTask = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) throw new HttpsError('failed-precondition', 'Please log in first.');
    const { repoId, goal } = request.data as { repoId?: string; goal?: string };
    if (!repoId || !goal) throw new HttpsError('invalid-argument', 'repoId and goal are required');
    // ...
  },
);
```

Codes used in this repo: `failed-precondition` (not logged in), `invalid-argument`
(missing/bad input), `not-found` (missing doc), `already-exists` (lock held).

---

## Distributed lock — always release in `finally`

`breakdownTask` acquires `repos/{repoId}.isBreakingDown` in a transaction, then wraps the
flow in `try { ... } finally { ... }` and releases the lock even on error, swallowing the
unlock error so it never masks the real failure (`handlers/breakdownTask.ts`):

```ts
try {
  return await breakdownTaskFlow({ repoId, goal, requestedBy: request.auth.uid });
} finally {
  await repoRef.update({ isBreakingDown: false }).catch(() => {});
}
```

A crash before `finally` is recovered by the `scheduledUnstickBreakdown` trigger (>5 min stale).

**Handler owns the lock — the flow must not touch it.** The `onCall` *handler*
(`handlers/breakdownTask.ts`) is the sole owner of `isBreakingDown`: it acquires the lock in a
transaction and releases it in `finally`. The *flow* (`flows/breakdownTask.ts`) only does
business logic (fetch context → OpenAI → write task docs) and must **never** read or write
`isBreakingDown`. (ARCHITECTURE §5.1 Step 6 mentions the flow unlocking — that is superseded by
this division: if the flow also unlocked, an early flow `return` would release the lock before
the handler's `finally`, defeating the guard.) Same split applies to every future AI flow:
handler = guard/lock/auth, flow = pure work + writes.

---

## Webhooks (`onRequest`) — verify first, respond fast

1. Verify the signature/secret before anything else; on failure respond `401` (GitHub HMAC
   via `x-hub-signature-256`; `discordMessageIngest` checks the `x-ingest-secret` shared key).
2. Validate payload shape → `400` on missing fields.
3. Idempotency dedupe (`x-github-delivery` / Discord `messageId`) → respond `200 dup`.
4. Respond `200` within seconds (GitHub retries after ~10 s). Only normalize + write the raw
   doc here; push all heavy logic to the matching Firestore trigger. See `ARCHITECTURE.md §6.3`.

---

## Triggers — idempotency + Rule D

Triggers are at-least-once. Guard with `markIdempotent(event.id)` first; do slow OpenAI/GitHub
calls *after* the idempotency transaction commits (never inside it), then write results back.
On external-call failure, log and leave the enrichment field null (MVP) rather than re-throwing
in a way that loses the event.

---

## External API calls — always bounded

Every GitHub / OpenAI / Discord call must have a timeout; never wait forever
(`AI_AGENT_RULES.md §3.6`). For best-effort side-effects (e.g. `notifyDiscord`), swallow the
error with `.catch()` + a log — a failed notification must not fail the main write.

**Optional / secondary signal tools must be best-effort, never throw into the parent flow.**
When an agentic flow registers a *supporting* tool (one signal among several — e.g.
`searchMemberCommits` in `assignTaskFlow`, alongside workload / expertise / dependents), that
tool must `try/catch` its query and `return` an empty/neutral result on any failure, logging at
`warn`. A single optional signal must not be able to abort the whole flow. Concrete incident
(2026-06): `searchMemberCommits`'s vector `findNearest` threw `9 FAILED_PRECONDITION: Missing
vector index configuration` (index not yet deployed) and killed every downstream assignment —
`assigneeId` stayed null. Fix: wrap the `embed()` + `findNearest()` + result map in one
`try/catch → return []`, so assignment finalizes on the remaining signals. Corollary: a feature
must not hard-depend on a **user-deployed** Firestore index (indexes are the user's job per
`AI_AGENT_RULES §R2`) — degrade gracefully when it is absent. And match the index `queryScope`
to the query: a `.collection(...)` `findNearest` needs a `COLLECTION`-scoped index, NOT
`COLLECTION_GROUP` (see `database-guidelines.md`), or the deployed index silently won't match.

**Best-effort registration pattern** (`addRepo` webhook): when an external resource can't yet be
created end-to-end (dependency not ready / not deployed), wrap it in `try/catch`, log on failure,
and persist a null id so a later backfill can retry — never block the primary write. Generate and
store any secret *before* the try so it survives the failure path:

```ts
const secret = crypto.randomBytes(32).toString('hex'); // always persisted
let webhookId: number | null = null;
try {
  webhookId = await registerWebhook(owner, repo, token, { url, secret, events });
} catch (e) {
  logger.warn('webhook registration failed; continuing (backfill later)', { repoId, err: String(e) });
}
// ... write repo doc with { webhookId, webhookSecret: secret } in the batch
```

---

## AI flow shape: agentic vs single-completion (pick by caller)

Two flow shapes exist; pick by how the flow is invoked:

- **Agentic function-calling loop** (`assignTaskFlow`, `summarizeDay`, `dailyBriefChat`,
  `breakdownTask`'s incremental path) — for user-initiated callables that benefit from the model
  drilling into data over several rounds.
- **Single-completion with pre-gathered context** (`explainCommit`, `discordDailyDigest`, and
  06-06 `generateHandoff`) — deterministically fetch all context, make ONE completion. **This is
  the required shape when the flow runs best-effort from a trigger** (e.g. `onTaskUpdated` calls
  `generateHandoffFlow`): bounded latency/cost, no multi-round loop that could stall the trigger,
  and easy to unit-test (seed Firestore + scripted OpenAI). Keep every context-gather in its own
  `try/catch → []/null` (commit query may need an undeployed composite index; Discord search and
  roster reads are optional signals) so the one OpenAI call still runs on partial context.

### Gotcha: answer EVERY tool_call in a turn before the next completion (all agentic loops)

A single assistant turn can batch **multiple** `tool_calls` — including a *supporting* read tool AND the **terminator** tool (`submitBreakdown` / `finalizeAssignment` / …) in the same turn. The OpenAI API contract: *the next* `chat.completions.create` rejects with **400** if any prior `tool_call` id lacks a matching `role:'tool'` reply ("an assistant message with tool_calls must be followed by tool messages responding to each tool_call_id").

The trap is the `continue` paths (malformed terminator args → retry; cycle detected → re-prompt): if you handle only the terminator's `tool_call` and `continue`, the sibling read calls are left **unanswered**, and the loop's next round 400s. This is **live-only** — fake-OpenAI unit mocks don't enforce the contract, so it passes CI and breaks in production.

**Rule:** every round, push a `role:'tool'` reply for **all** non-terminator tool calls FIRST, then handle the terminator (mirrors `assignTaskFlow`'s invalid-finalize path). Lock it with an invariant test (`assertNoDanglingToolCalls`) that checks every assistant `tool_call` id (except the loop-ending submit) got a tool reply.

```typescript
// WRONG — sibling read call dangles when submit args are malformed / cyclic
for (const call of toolCalls) {
  if (call.function.name === 'submitBreakdown') {
    if (!valid) { messages.push(errReply(call.id)); continue; } // ← read call never answered → next create() 400s
    return finalize(...);
  }
}
// CORRECT — answer all read calls first, then the terminator
for (const call of toolCalls.filter(c => c.function.name !== 'submitBreakdown')) {
  messages.push({ role: 'tool', tool_call_id: call.id, content: await runTool(call) });
}
const submit = toolCalls.find(c => c.function.name === 'submitBreakdown');
if (submit) { /* validate → reply-or-retry → finalize */ }
```

### Convention: one flow, two shapes auto-split by data state (incremental breakdown)

`breakdownTaskFlow` picks its shape from a cheap probe of repo state, NOT a caller flag (prd
06-15). A single `.limit(1).get()` on `repos/{repoId}/tasks` decides:

- **Empty repo → single-completion** `beta.chat.completions.parse` first pass (unchanged, low risk).
- **Non-empty repo → agentic function-calling loop** so the model EXPLORES the existing tasks +
  real project state via repo-scoped TOOLS and adds only the missing subtasks.

Load-bearing rules this established:

- **Never dump the queried set into the prompt when it grows unbounded.** The incremental path must
  not embed the existing task list in any system/user message — that would make context grow with
  task count. Existing tasks are reached only through paginated/limited tools
  (`listExistingTaskTitles` page size 25 + cursor; `searchExistingTasks` keyword, small limit) that
  return the minimal fields (`{taskId,title,status[,dependsOn]}`, prd D4 — no descriptions). The
  unit test asserts the flow-authored messages do NOT contain existing titles.
- **Terminator tool carries the structured output.** The loop ends on a `submitBreakdown({subtasks})`
  tool call whose args are Zod-validated (`IncrementalBreakdownSchema`); malformed args feed the
  error back for a retry. Running out of `MAX_ROUNDS` WITHOUT a valid submit **throws** — never
  silently write a partial/empty breakdown.
- **Cross-entity `dependsOn` is resolved at the write boundary.** A subtask may depend on other NEW
  subtasks (`dependsOnNew`: 0-based indices into the batch) AND on EXISTING tasks
  (`dependsOnExisting`: real taskIds). Pre-generate the new Firestore ids, translate both kinds into
  one `dependsOn: string[]`, and DROP unknown `dependsOnExisting` refs with a `logger.warn` (don't
  trust the model's ids).
- **Cycle detection spans the COMBINED graph.** Build `existing tasks (stored dependsOn) + new
  tasks (resolved deps)` keyed by taskId (`hasCycleById`) — the index-only `detectCycles` is for the
  first-pass path. A cycle re-prompts ONCE with feedback appended; a second cycle throws. The graph
  read (`readExistingTaskGraph`) is NOT best-effort — a failed read must not let us write on an
  unverified graph.
- **Repo isolation is the test contract.** Every tool path is `apps/gitsync/repos/{repoId}/tasks/…`;
  a test seeds two repos and asserts the tools only return the requested repo's tasks. Member
  expertise (`users/{uid}.expertiseTags`) stays deliberately cross-repo (prd D2) — untouched here.

### Convention: `force` flag splits manual-regenerate from auto-cache

A flow that both (a) auto-runs from a trigger and (b) is exposed as a manual "regenerate" callable
takes a `force?: boolean`. The flow returns the cached field when `!force && existing`; the manual
**handler** passes `force: true` (always fresh), the **trigger** passes `force: false` (fill only
if absent, so re-firing on each newly-landed prerequisite doesn't redo work). Mirrors
`explainCommit`'s cache. The cache write-back is best-effort (Rule D) — log + return the markdown
even if the `update()` fails, so the caller still gets the result.

### Convention: GitHub OAuth token capture + the 401 "reconnect" marker (06-16)

The `users/{uid}.githubAccessToken` (a `gho_` token, scopes `repo`+`read:user`) powers all
GitHub-calling backend code (`getCommitGraph`, `onTaskCreated` createIssue, `explainCommit` diff
fallback). It is captured **two ways**, because of a Firebase platform gap:

- **Web** — `firebase_auth` `signInWithPopup(GithubAuthProvider)` returns an `OAuthCredential`
  whose `.accessToken` is the token; stored at sign-in (`authentication.dart`).
- **Android** — `signInWithProvider` returns a **base `AuthCredential`, NOT `OAuthCredential`**, so
  `.accessToken` is null — the GitHub token is **unobtainable from `firebase_auth` on Android**
  (platform limitation, not an app bug). So Android (and any token refresh) uses a **secondary
  OAuth code flow**: `flutter_web_auth_2` runs GitHub's authorize URL (with a CSRF `state`) →
  `code` → the **`exchangeGitHubCode` `onCall`** swaps it for the token and writes it back.

**Rules this established:**
- **client_secret lives ONLY in a Cloud Function**, via `defineSecret('GITHUB_OAUTH_CLIENT_SECRET')`
  read with `.value()` inside `exchangeGitHubCode`. NEVER in Dart / AppConfig / the APK (the client
  holds only the public `client_id` and sends `{code, redirectUri}`). The token-exchange helper must
  not put the secret in any thrown message or log.
- **The exchange CF returns `{ok:true}`, never the token.** It validates `request.auth`, that the
  granted scope contains `repo`+`read:user`, and writes `apps/gitsync/users/{request.auth.uid}.githubAccessToken` (merge).
- **Stale-token marker:** a GitHub `401 Bad credentials` from a token consumer (e.g.
  `getCommitGraph`) must map to a **distinct** `HttpsError('failed-precondition', 'github-token-invalid: …')`
  (only 401 — other failures stay `unavailable`/`internal`). The app matches the `github-token-invalid`
  marker and surfaces a "Reconnect GitHub" CTA that re-runs the OAuth code flow. Owner config:
  GitHub OAuth App callback `gitsync://oauth/github` + `firebase functions:secrets:set GITHUB_OAUTH_CLIENT_SECRET`.

---

## Common mistakes

- Returning a plain object on error instead of throwing `HttpsError` (client can't distinguish).
- Putting a third-party `client_secret` anywhere client-side (Dart/AppConfig/APK) — it belongs in a
  Cloud Function `defineSecret` only; the client does the user-facing OAuth and posts the `code`.
- Assuming `firebase_auth` gives you the GitHub provider token on Android — it does not (see the
  GitHub OAuth convention above); use the `exchangeGitHubCode` flow.
- Adding a second Firestore trigger on a path another trigger already watches — the shared
  `event.id` makes `markIdempotent` swallow it (see database-guidelines Rule D.1); fold the concern
  into the existing trigger instead.
- Doing OpenAI work inside the idempotency transaction (Rule D) → lost data on retry.
- Forgetting the lock `finally` → repo stuck "breaking down".
- Heavy logic in the webhook handler → GitHub timeout + retry storm.
