// taskSnapshot (callables) — save / restore a full snapshot of a repo's task
// board so a demo can be reset to a known-good state and re-run reproducibly.
//
// A snapshot captures EVERYTHING the in-app demo cares about:
//   - every task's full doc (id preserved → dependsOn references stay valid;
//     assigneeId, content, status, githubIssueNumber, acceptanceCriteria, …)
//   - every member's expertiseTags + workload counters (activeIssueCount,
//     completedTaskCount) — these are NOT derivable from tasks alone.
//
// Restore = delete-all current tasks, recreate the snapshot tasks with their
// ORIGINAL ids (so dependsOn keeps working and onTaskCreated skips re-opening a
// GitHub issue because githubIssueNumber is already set), then write the member
// state back LAST so it reflects the snapshot, not any in-flight trigger churn.
//
// Single slot per repo: snapshots/latest (save overwrites). Best-effort GitHub
// side: the delete step still fires onTaskDeleted (which closes mirror issues);
// re-opening them is out of scope — the demo state restored is the in-app board.
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';

import { db, REGION } from '../admin';

const BATCH_LIMIT = 500;
const SNAPSHOT_DOC = 'latest';

interface SnapshotTask {
  id: string;
  data: Record<string, unknown>;
}
interface SnapshotMember {
  id: string;
  expertiseTags: string[];
  activeIssueCount: number;
  completedTaskCount: number;
}

function requireRepoId(request: { auth?: unknown; data: unknown }): string {
  if (!request.auth) {
    throw new HttpsError('failed-precondition', 'Please log in first.');
  }
  const { repoId } = (request.data ?? {}) as { repoId?: string };
  if (!repoId) {
    throw new HttpsError('invalid-argument', 'repoId is required');
  }
  return repoId;
}

/** Capture every task + member state into snapshots/latest (overwrites). */
export const saveTaskSnapshot = onCall({ region: REGION }, async (request) => {
  const repoId = requireRepoId(request);

  const [tasksSnap, membersSnap] = await Promise.all([
    db.collection(`apps/gitsync/repos/${repoId}/tasks`).get(),
    db.collection(`apps/gitsync/repos/${repoId}/members`).get(),
  ]);

  const tasks: SnapshotTask[] = tasksSnap.docs.map((d) => ({
    id: d.id,
    data: d.data() ?? {},
  }));
  const members: SnapshotMember[] = membersSnap.docs.map((d) => {
    const m = d.data() ?? {};
    return {
      id: d.id,
      expertiseTags: (m.expertiseTags as string[] | undefined) ?? [],
      activeIssueCount: (m.activeIssueCount as number | undefined) ?? 0,
      completedTaskCount: (m.completedTaskCount as number | undefined) ?? 0,
    };
  });

  await db
    .doc(`apps/gitsync/repos/${repoId}/snapshots/${SNAPSHOT_DOC}`)
    .set({
      savedAt: FieldValue.serverTimestamp(),
      taskCount: tasks.length,
      memberCount: members.length,
      tasks,
      members,
    });

  logger.info('saveTaskSnapshot: saved', {
    repoId,
    tasks: tasks.length,
    members: members.length,
  });
  return { taskCount: tasks.length, memberCount: members.length };
});

/** Restore the saved snapshot: replace all tasks and member workload/tags. */
export const restoreTaskSnapshot = onCall(
  { region: REGION, timeoutSeconds: 300 },
  async (request) => {
    const repoId = requireRepoId(request);

    const snapRef = db.doc(`apps/gitsync/repos/${repoId}/snapshots/${SNAPSHOT_DOC}`);
    const snap = await snapRef.get();
    if (!snap.exists) {
      throw new HttpsError('not-found', 'No saved snapshot for this repo.');
    }
    const data = snap.data() ?? {};
    const tasks = (data.tasks as SnapshotTask[] | undefined) ?? [];
    const members = (data.members as SnapshotMember[] | undefined) ?? [];

    // 1. Delete every current task (paged batches). onTaskDeleted fires per doc.
    const taskCol = db.collection(`apps/gitsync/repos/${repoId}/tasks`);
    let deleted = 0;
    for (;;) {
      const cur = await taskCol.limit(BATCH_LIMIT).get();
      if (cur.empty) break;
      const batch = db.batch();
      for (const doc of cur.docs) batch.delete(doc.ref);
      await batch.commit();
      deleted += cur.size;
      if (cur.size < BATCH_LIMIT) break;
    }

    // 2. Recreate snapshot tasks with their ORIGINAL ids (dependsOn stays valid;
    //    onTaskCreated skips issue creation because githubIssueNumber is set).
    for (let i = 0; i < tasks.length; i += BATCH_LIMIT) {
      const batch = db.batch();
      for (const t of tasks.slice(i, i + BATCH_LIMIT)) {
        batch.set(taskCol.doc(t.id), t.data);
      }
      await batch.commit();
    }

    // 3. Restore member tags + workload counters LAST so the snapshot values win
    //    over any recompute the delete/create triggers performed mid-restore.
    if (members.length > 0) {
      const batch = db.batch();
      for (const m of members) {
        batch.set(
          db.doc(`apps/gitsync/repos/${repoId}/members/${m.id}`),
          {
            expertiseTags: m.expertiseTags,
            activeIssueCount: m.activeIssueCount,
            completedTaskCount: m.completedTaskCount,
          },
          { merge: true },
        );
      }
      await batch.commit();
    }

    logger.info('restoreTaskSnapshot: restored', {
      repoId,
      deleted,
      restoredTasks: tasks.length,
      restoredMembers: members.length,
    });
    return { restoredTasks: tasks.length, restoredMembers: members.length };
  },
);
