// onTaskUpdated — when a task transitions to `done`, auto-assign now-ready
// downstream tasks (reusing assignTaskFlow) and FCM-notify each newly-ready
// downstream task's assignee. See prd.md (06-02-auto-assign-on-done) and
// ARCHITECTURE.md §4.3 (TODO a/b).
//
// Why onDocumentUpdated (not onDocumentWritten): tasks are CREATED `todo` and
// only later UPDATED to `done`, so the terminal-state transition is a genuine
// update (contrast onPRMerged, where handlePR creates the doc already merged —
// database-guidelines Rule E).
import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION, db } from '../admin';
import { openaiKey } from '../config';
import { assignTaskFlow } from '../flows/assignTask';
import { markIdempotent } from '../tools/idempotency';
import { notifyAssignee } from '../tools/notify';

export const onTaskUpdated = onDocumentUpdated(
  {
    document: 'apps/gitsync/repos/{repoId}/tasks/{taskId}',
    region: REGION,
    // assignTaskFlow calls OpenAI → needs the key + a longer budget for several
    // downstream agentic loops.
    secrets: [openaiKey],
    timeoutSeconds: 300,
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // Transition guard: only act on the FIRST transition into `done`. This also
    // prevents recursion — when assignTaskFlow writes a downstream task's
    // assigneeId this trigger re-fires, but that task's status didn't transition
    // to done, so we return here.
    if (before.status === 'done' || after.status !== 'done') return;

    const { repoId, taskId: completedTaskId } = event.params as {
      repoId: string;
      taskId: string;
    };
    logger.info('onTaskUpdated: task done, processing downstream', {
      repoId,
      completedTaskId,
    });

    // Downstream tasks: those whose dependsOn array-contains the completed task.
    // Single array-contains → Firestore auto-indexes (no composite needed).
    const downstreamSnap = await db
      .collection(`apps/gitsync/repos/${repoId}/tasks`)
      .where('dependsOn', 'array-contains', completedTaskId)
      .get();

    for (const doc of downstreamSnap.docs) {
      // Best-effort per downstream task: one failure must not abort the rest,
      // and the trigger must never throw (avoids at-least-once retry storms).
      try {
        const b = doc.data() ?? {};
        const dependsOn = (b.dependsOn as string[] | undefined) ?? [];

        // Ready filter: every prerequisite of B must be `done`. The completed
        // task A is one of them; confirm all the others too.
        const ready = await allPrereqsDone(repoId, dependsOn, completedTaskId);
        if (!ready) {
          logger.info('onTaskUpdated: downstream not ready, skipping', {
            repoId,
            downstreamId: doc.id,
          });
          continue;
        }

        // Assign if unassigned (reuse assignTaskFlow — it writes assigneeId and
        // balances counters via applyAssignment). Never overwrite a manual
        // assignment / call OpenAI when already assigned.
        let assigneeId = b.assigneeId as string | undefined;
        if (!assigneeId) {
          const result = await assignTaskFlow({ repoId, taskId: doc.id });
          assigneeId = result.assigneeId;
        }

        // Notify the (new or existing) assignee that B is now unblocked.
        if (assigneeId) {
          await notifyAssignee(assigneeId, {
            title: '有新任務可以開始了',
            body: String(b.title ?? doc.id),
          });
        }
      } catch (e) {
        logger.error('onTaskUpdated: downstream processing failed', {
          repoId,
          downstreamId: doc.id,
          error: String(e),
        });
      }
    }
  },
);

/**
 * True iff every prerequisite task id has `status === 'done'`. `completedId` is
 * known-done (it just transitioned), so we skip re-reading it.
 */
async function allPrereqsDone(
  repoId: string,
  dependsOn: string[],
  completedId: string,
): Promise<boolean> {
  for (const prereqId of dependsOn) {
    if (prereqId === completedId) continue;
    const snap = await db
      .doc(`apps/gitsync/repos/${repoId}/tasks/${prereqId}`)
      .get();
    if ((snap.data() ?? {}).status !== 'done') return false;
  }
  return true;
}
