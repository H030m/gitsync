// breakdownTask (callable) — entry point for the breakdownTask AI flow.
// Owns the distributed lock (`isBreakingDown` flag). See ARCHITECTURE.md §5.1.
import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { db, REGION } from '../admin';
import { openaiKey } from '../config';
import { breakdownTaskFlow } from '../flows/breakdownTask';

export const breakdownTask = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, goal } = request.data as { repoId?: string; goal?: string };
    if (!repoId || !goal) {
      throw new HttpsError('invalid-argument', 'repoId and goal are required');
    }

    // Acquire the distributed lock atomically.
    const repoRef = db.doc(`apps/gitsync/repos/${repoId}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(repoRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', `repo ${repoId} not found`);
      }
      if (snap.data()?.isBreakingDown === true) {
        throw new HttpsError(
          'already-exists',
          'A breakdown is already running for this repo.',
        );
      }
      tx.update(repoRef, {
        isBreakingDown: true,
        breakdownStartedAt: new Date(),
      });
    });

    try {
      return await breakdownTaskFlow({
        repoId,
        goal,
        requestedBy: request.auth.uid,
      });
    } finally {
      // Always release the lock, even on error. Swallow the unlock error so
      // it never masks the real failure reported above.
      await repoRef.update({ isBreakingDown: false }).catch(() => {});
    }
  },
);
