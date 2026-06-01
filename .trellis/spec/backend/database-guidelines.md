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

## Timestamps

- Server-authored times use `FieldValue.serverTimestamp()` on write (`createdAt`, `updatedAt`,
  `processedAt`). Don't persist client clock values for these.
