import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { markIdempotent } from '../tools/idempotency';

export const onTaskUpdated = onDocumentUpdated(
  {
    document: 'apps/gitsync/repos/{repoId}/tasks/{taskId}',
    region: REGION,
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;

    // TODO Sprint 3:
    //  - When status changes todo/in_progress → done:
    //    a. Query downstream tasks via `dependsOn` array-contains
    //    b. Send FCM to their assignees
    //    c. POST to Discord webhook (notifyDiscord)
    //    d. Trigger generateHandoffFlow and write `tasks/{id}.handoffDoc`
    //  - Update `members.{previousAssignee/newAssignee}.activeIssueCount`
    //    via atomic increment in a transaction
    logger.info('onTaskUpdated stub', {
      ids: event.params,
      statusChange: `${before.status} → ${after.status}`,
    });
  },
);
