// addRepo (callable) — parses a GitHub URL, verifies the user's access via
// GitHub API, best-effort registers a webhook on the repo, and creates the
// matching Firestore docs (`repos/{repoId}` + `users/{uid}/repos/{repoId}` +
// `repos/{repoId}/members/{uid}`).
//
// See ARCHITECTURE.md §6.2 for the full flow.
import { randomBytes } from 'node:crypto';

import { logger } from 'firebase-functions/v2';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';

import { db, REGION } from '../admin';
import { registerWebhook, verifyRepoAccess } from '../services/githubClient';
import { parseGithubUrl } from '../tools/githubUrl';

// Re-exported so existing importers (and tests) can keep importing it from here.
export { parseGithubUrl };

const WEBHOOK_EVENTS = ['push', 'pull_request', 'issues', 'issue_comment'];

export const addRepo = onCall(
  { region: REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const uid = request.auth.uid;

    const { githubUrl } = request.data as { githubUrl?: string };
    if (!githubUrl || typeof githubUrl !== 'string') {
      throw new HttpsError('invalid-argument', 'githubUrl is required');
    }

    const parsed = parseGithubUrl(githubUrl);
    if (!parsed) {
      throw new HttpsError(
        'invalid-argument',
        'githubUrl could not be parsed into owner/repo',
      );
    }
    const { owner, repo } = parsed;

    // 1. Look up the caller's stored GitHub access token.
    const userSnap = await db.doc(`apps/gitsync/users/${uid}`).get();
    const githubAccessToken = userSnap.data()?.githubAccessToken as
      | string
      | undefined;
    if (!githubAccessToken) {
      throw new HttpsError(
        'failed-precondition',
        'No GitHub access token found. Please complete GitHub authorization first.',
      );
    }

    // 2. Verify the repo exists and the caller has admin/push permission.
    let access;
    try {
      access = await verifyRepoAccess(owner, repo, githubAccessToken);
    } catch (err) {
      const status = (err as { status?: number }).status;
      if (status === 404) {
        throw new HttpsError(
          'not-found',
          `Repository ${owner}/${repo} not found or not accessible.`,
        );
      }
      logger.error('verifyRepoAccess failed', { owner, repo, status });
      throw new HttpsError(
        'failed-precondition',
        `Could not verify access to ${owner}/${repo}.`,
      );
    }
    if (!access.permissions.admin && !access.permissions.push) {
      throw new HttpsError(
        'failed-precondition',
        `You do not have push/admin permission on ${owner}/${repo}.`,
      );
    }

    // 3. repoId = `${owner}_${name}`; reject duplicates.
    const repoId = `${owner}_${repo}`;
    const repoRef = db.doc(`apps/gitsync/repos/${repoId}`);
    const existing = await repoRef.get();
    if (existing.exists) {
      throw new HttpsError(
        'already-exists',
        `Repository ${repoId} has already been added.`,
      );
    }

    // 4. Best-effort webhook registration. Failure (OAuth/deploy URL/perms not
    //    ready) must not block repo creation — log and continue with null id.
    const webhookSecret = randomBytes(32).toString('hex');
    let webhookId: number | null = null;
    try {
      const webhookUrl =
        `https://${REGION}-${process.env.GCLOUD_PROJECT}` +
        '.cloudfunctions.net/githubWebhook';
      webhookId = await registerWebhook(owner, repo, githubAccessToken, {
        url: webhookUrl,
        secret: webhookSecret,
        events: WEBHOOK_EVENTS,
      });
    } catch (err) {
      logger.warn('registerWebhook failed (best-effort), continuing', {
        repoId,
        status: (err as { status?: number }).status,
      });
      webhookId = null;
    }

    // 5. Atomically write all three docs.
    const batch = db.batch();
    batch.set(repoRef, {
      // Display name is the full `owner/repo` slug (ARCHITECTURE §2.1 example
      // "team17/gitsync"); repoId already encodes owner as `${owner}_${repo}`.
      name: `${owner}/${repo}`,
      url: githubUrl,
      githubRepoId: access.githubRepoId,
      defaultBranch: access.defaultBranch,
      webhookId,
      webhookSecret,
      memberIds: [uid],
      isBreakingDown: false,
      createdAt: FieldValue.serverTimestamp(),
      createdBy: uid,
    });
    batch.set(db.doc(`apps/gitsync/users/${uid}/repos/${repoId}`), {
      role: 'owner',
    });
    batch.set(db.doc(`apps/gitsync/repos/${repoId}/members/${uid}`), {
      role: 'owner',
      activeIssueCount: 0,
      completedTaskCount: 0,
      lastActiveAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();

    return { repoId };
  },
);
