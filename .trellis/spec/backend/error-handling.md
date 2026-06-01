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

## Common mistakes

- Returning a plain object on error instead of throwing `HttpsError` (client can't distinguish).
- Doing OpenAI work inside the idempotency transaction (Rule D) → lost data on retry.
- Forgetting the lock `finally` → repo stuck "breaking down".
- Heavy logic in the webhook handler → GitHub timeout + retry storm.
