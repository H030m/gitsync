// deleteAllTasks (callable) — bulk-deletes EVERY task in a repo. Used by the
// Settings "delete all tasks" action to reset the board (e.g. before a demo).
//
// Each delete fires onTaskDeleted, which closes the task's mirrored GitHub issue
// IF it has one (AI-breakdown tasks carry githubIssueNumber: null → no-op). The
// delete is chunked into Firestore batches of <=500 ops.
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { db, REGION } from '../admin';

const BATCH_LIMIT = 500;

export const deleteAllTasks = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('failed-precondition', 'Please log in first.');
  }
  const { repoId } = request.data as { repoId?: string };
  if (!repoId) {
    throw new HttpsError('invalid-argument', 'repoId is required');
  }

  const col = db.collection(`apps/gitsync/repos/${repoId}/tasks`);
  let deleted = 0;
  // Page through the collection deleting in batches until it's empty.
  for (;;) {
    const snap = await col.limit(BATCH_LIMIT).get();
    if (snap.empty) break;
    const batch = db.batch();
    for (const doc of snap.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += snap.size;
    if (snap.size < BATCH_LIMIT) break;
  }

  // No tasks remain → every member's active workload is 0. Set it deterministically
  // here rather than relying on the per-doc onTaskDeleted recompute (which fires
  // async and would race across a 500-doc batch). Best-effort: a counter failure
  // must not fail the (already completed) clear.
  try {
    const members = await db
      .collection(`apps/gitsync/repos/${repoId}/members`)
      .get();
    if (!members.empty) {
      const batch = db.batch();
      for (const m of members.docs) {
        batch.set(m.ref, { activeIssueCount: 0 }, { merge: true });
      }
      await batch.commit();
    }
  } catch (err) {
    logger.warn('deleteAllTasks: zeroing member workload failed (best-effort)', {
      repoId,
      err: String(err),
    });
  }

  logger.info('deleteAllTasks: cleared tasks', { repoId, deleted });
  return { deleted };
});
