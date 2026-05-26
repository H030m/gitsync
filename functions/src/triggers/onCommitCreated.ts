import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { shouldSkipEmbedding } from '../tools/commitFilter';
import { markIdempotent } from '../tools/idempotency';

export const onCommitCreated = onDocumentCreated(
  {
    document: 'apps/gitsync/repos/{repoId}/commits/{sha}',
    region: REGION,
    secrets: [openaiKey],
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    const commit = event.data?.data();
    if (!commit) return;

    const message = commit.message as string | undefined;
    if (!message) return;

    if (shouldSkipEmbedding(message)) {
      logger.info('Skipping commit embedding (filter hit)', { sha: event.params.sha });
      return;
    }

    // TODO Sprint 4:
    //  1. Parse `#N` / `fixes #N` from the message and set `linkedTaskIds`
    //  2. Compute embedding (tools/embedding.ts) and write back as
    //     `messageEmbedding: FieldValue.vector(...)`
    //  3. Generate `aiSummary` via gpt-4o-mini
    logger.info('onCommitCreated stub', { ids: event.params });
  },
);
