import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { markIdempotent } from '../tools/idempotency';

export const onTaskCreated = onDocumentCreated(
  {
    document: 'apps/gitsync/repos/{repoId}/tasks/{taskId}',
    region: REGION,
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    // TODO Sprint 3:
    //  - If `source === 'manual'` and assignment is requested, run assignTaskFlow
    //  - Create a matching GitHub issue (if repo wants issues mirrored)
    //  - Increment `members/{assigneeId}.activeIssueCount` if assigned
    logger.info('onTaskCreated stub', { ids: event.params });
  },
);
