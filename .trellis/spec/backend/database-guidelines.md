# Database Guidelines (Firestore)

> No ORM, no migrations. Database is **Cloud Firestore** accessed via firebase-admin
> on the backend and `cloud_firestore` on the frontend.
> Schema source of truth: [`docs/ARCHITECTURE.md §2`](../../../docs/ARCHITECTURE.md).

---

## Path convention (non-negotiable)

**Every collection lives under `apps/gitsync/`.** Never write to root `users/` or `repos/`.
This mirrors the course `group-todo-list` example (see [`MEMORY.md 2026-05-20`](../../../docs/MEMORY.md)).

```
apps/gitsync/users/{userId}
apps/gitsync/repos/{repoId}
apps/gitsync/repos/{repoId}/{tasks|commits|pullRequests|discordMessages|dailyReports|members}/{id}
apps/gitsync/idempotencyKeys/{eventId}
```

Backend builds the literal path from `repoId` params. The frontend mirror is
`lib/repositories/firestore_paths.dart`. See `ARCHITECTURE.md §2.1` for the full
field-by-field schema of every collection.

---

## Who may write what (mirror the security rules)

`firestore.rules` enforces this; schema design depends on it ([`ARCHITECTURE.md §2.2`](../../../docs/ARCHITECTURE.md)):

- `commits` / `pullRequests` / `discordMessages` / `dailyReports` → `allow write: if false`.
  **Only Cloud Functions (admin SDK) write these.** The Flutter app only reads them.
- `tasks` / `users` / repo root → the app writes (rules check membership / ownership).
- Never invent a new collection or field without proposing it in `docs/MEMORY.md` first.

---

## Concurrency rules (triggers & webhooks run concurrently)

From [`ARCHITECTURE.md §4.4`](../../../docs/ARCHITECTURE.md) — violating these corrupts counters/state:

- **Rule A — counters use atomic ops.** Any numeric field (`activeIssueCount`,
  `completedTaskCount`) must use `FieldValue.increment(±1)`. Never read-then-write.
- **Rule B — cross-field/cross-doc changes use `runTransaction`.** Read inside the
  transaction to guard idempotency (e.g. "task not already done"), then update.
- **Rule C — every Firestore trigger does an idempotency check.** Triggers are
  at-least-once. Use `markIdempotent(event.id)` from `tools/idempotency.ts`:
  ```ts
  const fresh = await markIdempotent(event.id);
  if (!fresh) return; // already processed
  ```
- **Rule D — never put slow side-effects in the idempotency transaction.** Mark the key,
  *exit* the transaction, *then* call OpenAI / GitHub, then write results back. MVP accepts
  an occasional null `aiSummary`/`embedding` on failure + a manual "regenerate" button.
- **Rule E — match the trigger type to how the source doc is written.** If the producing
  write **creates** the doc already in its terminal state, `onDocumentUpdated` will **never
  fire** (it only fires on updates to an existing doc). The webhook's `handlePR` writes
  `pullRequests/{n}` directly as `state: 'merged'` (a create), so `onPRMerged` must be
  `onDocumentWritten`, guarding on the *transition into* the state:
  ```ts
  // onDocumentWritten — fires on create AND update
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!after) return;                                   // deletion → ignore
  if (after.state !== 'merged' || before?.state === 'merged') return; // transition guard
  ```
  Reserve `onDocumentUpdated` for docs that genuinely change *after* creation (e.g. a
  `tasks` doc edited by the app). The in-txn idempotent re-read still guards double-fires.
  Unit tests that call the raw handler with a synthetic `before/after` will pass either way —
  this gap only shows up live, so pick the trigger type deliberately.

---

## Vector search (Firestore native `findNearest`)

- Embeddings stored as `FieldValue.vector(...)`, dimension `1536` (`EMBEDDING_DIM` in
  `config.ts`, model `text-embedding-3-small`).
- A `findNearest` query **must** carry `.where('repoId', '==', repoId)` to avoid cross-repo
  leakage — that's why `commits`/`discordMessages`/`pullRequests` redundantly store `repoId`.
- Required vector + composite indexes live in `firestore.indexes.json`.
  **Creating/deploying indexes is the user's job** (`firebase deploy --only firestore:indexes`),
  never the AI's — see `AI_AGENT_RULES.md §R2`.
- Before embedding a commit, call `shouldSkipEmbedding(message)` (`tools/commitFilter.ts`) to
  skip noise (`Merge ...`, version bumps, etc.).

---

## Rule F — producer must persist the field name the consumer prefilters on

When a doc is written by one function (producer) and a `findNearest` / `where` prefilter in
another (consumer) reads it, the **stored field name is a contract** — a mismatch fails
*silently* (query returns `[]`, no error). The schema in `ARCHITECTURE.md §2.1` is the single
source of truth for the key; the inbound payload's key is irrelevant and often differs.

Concrete incident (2026-06): GitHub's `push` webhook payload delivers the author handle as
`commits[].author.username`, but the canonical schema is `commits.author.login` and
`searchMemberCommits` prefilters `.where('author.login','==',githubLogin)`. `handlePush` had
persisted it under `author.username`, so the vector search always returned nothing. Fix: map
on write (`login: payload.author.username`), not on read.

Before writing a doc that something else queries: open `ARCHITECTURE.md §2.1`, copy the exact
field name, and (if the payload key differs) translate at the write site. Unit tests that mock
the consumer's Firestore won't catch this — trace the **actual producer** (as in Rule E).

---

## Rule G — prefer single `array-contains` + in-code filter over a composite index

A query like `where('dependsOn','array-contains', id).where('status','==','todo')` needs a
**manually-created composite index** — and if it's missing the trigger *crashes at runtime*
(`FAILED_PRECONDITION`), not at deploy. Since index creation is the user's job
(`AI_AGENT_RULES §R2`), that's a live-only landmine.

When the second predicate is cheap and low-cardinality (a status enum, a boolean), run the
**single** `array-contains` query (auto-indexed, zero setup) and filter the rest in code. The
result set here is "tasks depending on X" — always small — so the in-memory filter is free.
`onTaskUpdated`'s downstream/ready check does exactly this. Reserve composite indexes for
queries whose prefilter genuinely must run server-side for scale (and then add the index to
`firestore.indexes.json` + flag the deploy command for the user).

---

## Deleting a repo (aggregate root) + its subcollections

Deleting a doc does **not** delete its subcollections — they orphan. To remove a `repos/{repoId}`
and everything under it (`members/tasks/commits/pullRequests/discordMessages/dailyReports`), use
the admin SDK's `db.recursiveDelete(repoRef)` (single call, handles all subcollections).

**Order matters** — delete cross-collection pointers (e.g. each member's
`users/{memberUid}/repos/{repoId}`, which live under `users/`, NOT under the repo) *before*
`recursiveDelete`:

```ts
await Promise.all(memberIds.map((m) =>
  db.doc(`apps/gitsync/users/${m}/repos/${repoId}`).delete()));
await db.recursiveDelete(db.doc(`apps/gitsync/repos/${repoId}`));
```

Pointers-first means a failure leaves the repo doc intact, so a retry is well-defined (and a
later read still returns the repo → no spurious `not-found`). The reverse order would orphan the
pointers permanently. Pair external cleanup (e.g. best-effort `deleteWebhook`) with this — see
`handlers/removeRepo.ts` and the best-effort pattern in [`error-handling.md`](./error-handling.md).

---

## Timestamps

- Server-authored times use `FieldValue.serverTimestamp()` on write (`createdAt`, `updatedAt`,
  `processedAt`). Don't persist client clock values for these.
