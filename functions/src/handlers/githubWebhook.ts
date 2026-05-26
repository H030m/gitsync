// githubWebhook (onRequest) — receives GitHub push / PR / issue events.
//
// IMPORTANT: This handler ONLY normalizes raw payloads and writes Firestore
// docs. All business logic (linking commits to tasks, computing embeddings,
// calling OpenAI) happens in the matching Firestore Trigger
// (`onCommitCreated`, `onPRMerged`, etc.). See MEMORY.md 2026-05-26
// "webhook only writes raw, trigger does AI" and ARCHITECTURE.md §6.3.
import { onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';

export const githubWebhook = onRequest(
  { region: REGION, maxInstances: 10 },
  async (req, res) => {
    // TODO Sprint 4:
    //  1. Verify HMAC-SHA256 of raw body against `repos/{repoId}.webhookSecret`
    //     using the `x-hub-signature-256` header (401 on mismatch)
    //  2. Idempotency: use `x-github-delivery` as key (200 'dup' on hit)
    //  3. Dispatch by `x-github-event` header to handlePush / handlePR / handleIssue
    //  4. Return 200 within 10s — no AI here
    logger.info('githubWebhook hit (skeleton)', { event: req.header('x-github-event') });
    res.status(200).send({ ok: true, note: 'githubWebhook is a stub' });
  },
);
