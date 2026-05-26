import { onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { markIdempotent } from '../tools/idempotency';

export const onPRMerged = onDocumentUpdated(
  {
    document: 'apps/gitsync/repos/{repoId}/pullRequests/{prNumber}',
    region: REGION,
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (before.state === 'merged' || after.state !== 'merged') return;

    // TODO Sprint 4:
    //  - Transaction: mark every task in `linkedTaskIds` as done (if not
    //    already), increment `members/{assigneeId}.completedTaskCount`
    //  - The transaction-internal read provides the idempotent guard
    //    (avoids double-count if the trigger fires twice)
    logger.info('onPRMerged stub', { ids: event.params });
  },
);
