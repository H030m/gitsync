// githubWebhook (onRequest) — receives GitHub push / PR / issue events.
//
// IMPORTANT: This handler ONLY normalizes raw payloads and writes Firestore
// docs. All business logic (linking commits to tasks, computing embeddings,
// calling OpenAI, marking tasks done) happens in the matching Firestore Trigger
// (`onCommitCreated`, `onPRMerged`, `onIssueWritten`). See MEMORY.md 2026-05-26
// "webhook only writes raw, trigger does AI" and ARCHITECTURE.md §6.3.
import { createHmac, timingSafeEqual } from 'node:crypto';

import { onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';

import { db, REGION } from '../admin';
import { markIdempotent } from '../tools/idempotency';

/**
 * Verifies the GitHub HMAC-SHA256 signature of the raw body against the repo's
 * stored `webhookSecret`. Uses `timingSafeEqual` (length-guarded) to avoid
 * timing leaks. Returns false on any mismatch / missing input.
 */
function verifySignature(
  rawBody: Buffer | undefined,
  signatureHeader: string | undefined,
  secret: string,
): boolean {
  if (!rawBody || !signatureHeader) return false;
  const expected =
    'sha256=' + createHmac('sha256', secret).update(rawBody).digest('hex');
  const expectedBuf = Buffer.from(expected);
  const actualBuf = Buffer.from(signatureHeader);
  if (expectedBuf.length !== actualBuf.length) return false;
  return timingSafeEqual(expectedBuf, actualBuf);
}

/**
 * Writes a raw commit doc per push commit. No `#N` parsing, no embeddings, no
 * linkedTaskIds — `onCommitCreated` (Layer 2) does all of that.
 *
 * Default-branch decision: GitHub `push` payloads carry `ref`
 * (`refs/heads/<branch>`) and `repository.default_branch`. We only persist
 * commits pushed to the default branch so non-default feature-branch pushes
 * don't create noise commit docs; the matching task-completion signal comes
 * from PR merges into the default branch anyway.
 */
async function handlePush(repoId: string, body: Record<string, unknown>): Promise<void> {
  const ref = body.ref as string | undefined;
  const repository = body.repository as { default_branch?: string } | undefined;
  const defaultBranch = repository?.default_branch;
  if (ref && defaultBranch && ref !== `refs/heads/${defaultBranch}`) {
    logger.info('Skipping push to non-default branch', { repoId, ref });
    return;
  }

  const commits = (body.commits as Array<Record<string, unknown>> | undefined) ?? [];
  if (commits.length === 0) return;

  const batch = db.batch();
  for (const c of commits) {
    const sha = c.id as string | undefined;
    if (!sha) continue;
    const author = (c.author as Record<string, unknown> | undefined) ?? {};
    const added = (c.added as string[] | undefined) ?? [];
    const removed = (c.removed as string[] | undefined) ?? [];
    const modified = (c.modified as string[] | undefined) ?? [];
    const ref2 = db.doc(`apps/gitsync/repos/${repoId}/commits/${sha}`);
    batch.set(ref2, {
      repoId,
      sha,
      message: (c.message as string | undefined) ?? '',
      author: {
        name: (author.name as string | undefined) ?? '',
        email: (author.email as string | undefined) ?? '',
        username: (author.username as string | undefined) ?? '',
      },
      url: (c.url as string | undefined) ?? '',
      filesChanged: added.length + removed.length + modified.length,
      added,
      removed,
      modified,
      committedAt: (c.timestamp as string | undefined) ?? null,
      createdAt: FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
}

/**
 * Writes a raw pullRequests doc, but ONLY for merged PRs (action closed +
 * merged true). `title`/`body` are persisted because `onPRMerged` (Layer 2)
 * parses closing keywords (`closes/fixes/resolves #N`) out of them. No task
 * status changes here.
 */
async function handlePR(repoId: string, body: Record<string, unknown>): Promise<void> {
  const action = body.action as string | undefined;
  const pr = body.pull_request as Record<string, unknown> | undefined;
  if (action !== 'closed' || !pr || pr.merged !== true) return;

  const number = pr.number as number | undefined;
  if (number === undefined) return;

  const head = (pr.head as Record<string, unknown> | undefined) ?? {};
  const base = (pr.base as Record<string, unknown> | undefined) ?? {};

  await db.doc(`apps/gitsync/repos/${repoId}/pullRequests/${number}`).set({
    repoId,
    number,
    title: (pr.title as string | undefined) ?? '',
    body: (pr.body as string | undefined) ?? '',
    state: 'merged',
    // GitHub's pull_request webhook payload does not include the commit SHA
    // list; Layer 2 (onPRMerged) can fetch them via the API if needed.
    commitShas: [],
    headBranch: (head.ref as string | undefined) ?? '',
    baseBranch: (base.ref as string | undefined) ?? '',
    mergedAt: (pr.merged_at as string | undefined) ?? null,
    createdAt: FieldValue.serverTimestamp(),
  });
}

/**
 * Upserts a raw issues doc mirroring GitHub's issue state. `onIssueWritten`
 * (Layer 2) reverse-syncs this into task status. No task writes here.
 */
async function handleIssue(repoId: string, body: Record<string, unknown>): Promise<void> {
  const action = body.action as string | undefined;
  const issue = body.issue as Record<string, unknown> | undefined;
  if (!issue) return;
  const number = issue.number as number | undefined;
  if (number === undefined) return;

  await db.doc(`apps/gitsync/repos/${repoId}/issues/${number}`).set(
    {
      repoId,
      number,
      state: (issue.state as string | undefined) ?? 'open',
      title: (issue.title as string | undefined) ?? '',
      action: action ?? '',
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export const githubWebhook = onRequest(
  { region: REGION, maxInstances: 10 },
  async (req, res) => {
    const body = (req.body ?? {}) as Record<string, unknown>;
    const repository = body.repository as
      | { name?: string; owner?: { login?: string } }
      | undefined;
    const owner = repository?.owner?.login;
    const repo = repository?.name;

    // 1. HMAC verify against repos/{repoId}.webhookSecret (raw body).
    if (!owner || !repo) {
      logger.warn('githubWebhook: missing repository owner/name in payload');
      res.status(401).send('invalid payload');
      return;
    }
    const repoId = `${owner}_${repo}`;

    const repoSnap = await db.doc(`apps/gitsync/repos/${repoId}`).get();
    const webhookSecret = repoSnap.data()?.webhookSecret as string | undefined;
    if (!repoSnap.exists || !webhookSecret) {
      logger.warn('githubWebhook: unknown repo or missing secret', { repoId });
      res.status(401).send('unknown repo');
      return;
    }

    const signature = req.header('x-hub-signature-256') ?? undefined;
    if (!verifySignature(req.rawBody, signature, webhookSecret)) {
      logger.warn('githubWebhook: signature verification failed', { repoId });
      res.status(401).send('invalid signature');
      return;
    }

    // 2. Idempotency via x-github-delivery.
    const deliveryId = req.header('x-github-delivery') ?? undefined;
    if (!deliveryId) {
      logger.warn('githubWebhook: missing x-github-delivery', { repoId });
      res.status(400).send('missing delivery id');
      return;
    }
    const fresh = await markIdempotent(deliveryId);
    if (!fresh) {
      logger.info('githubWebhook: duplicate delivery, skipping', { repoId, deliveryId });
      res.status(200).send({ ok: true, dup: true });
      return;
    }

    // 3. Dispatch by event type. Wrap so a thrown error still returns 200
    //    (avoid GitHub retry storms) but is logged at error level.
    const event = req.header('x-github-event') ?? undefined;
    try {
      switch (event) {
        case 'push':
          await handlePush(repoId, body);
          break;
        case 'pull_request':
          await handlePR(repoId, body);
          break;
        case 'issues':
          await handleIssue(repoId, body);
          break;
        default:
          logger.info('githubWebhook: ignoring event', { repoId, event });
      }
    } catch (err) {
      logger.error('githubWebhook: handler error (returning 200 to avoid retry storm)', {
        repoId,
        event,
        err: String(err),
      });
    }

    res.status(200).send({ ok: true });
  },
);
