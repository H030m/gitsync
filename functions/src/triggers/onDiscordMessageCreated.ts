import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { shouldKeepMessage } from '../tools/discordFilter';
import { markIdempotent } from '../tools/idempotency';

export const onDiscordMessageCreated = onDocumentCreated(
  {
    document: 'apps/gitsync/repos/{repoId}/discordMessages/{messageId}',
    region: REGION,
    secrets: [openaiKey],
  },
  async (event) => {
    const fresh = await markIdempotent(event.id);
    if (!fresh) return;

    const msg = event.data?.data();
    if (!msg) return;

    // Re-run the noise filter in case the forwarder rules drifted.
    if (!shouldKeepMessage({ content: msg.content as string })) {
      logger.info('Filtering Discord message (server-side noise check)');
      // We DON'T delete the doc — just skip embedding / linking work.
      return;
    }

    // TODO Sprint 4:
    //  1. Compute embedding (tools/embedding.ts) → write
    //     `discordMessages/{id}.embedding = FieldValue.vector(...)`
    //  2. AI-infer `linkedTaskIds` (small model, structured outputs)
    logger.info('onDiscordMessageCreated stub', { ids: event.params });
  },
);
