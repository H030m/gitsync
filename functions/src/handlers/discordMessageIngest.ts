// discordMessageIngest (onRequest) — receives normalized Discord messages from
// the forwarder bot. Verifies the shared secret, runs the noise filter, and
// writes the raw doc. AI work (embedding, linked-task detection) happens in
// `onDiscordMessageCreated`. See ARCHITECTURE.md §7.2.
import { onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';

import { REGION } from '../admin';
import { discordIngestSecret } from '../config';

export const discordMessageIngest = onRequest(
  { region: REGION, secrets: [discordIngestSecret], maxInstances: 10 },
  async (req, res) => {
    if (req.header('x-ingest-secret') !== discordIngestSecret.value()) {
      res.status(401).send({ error: 'bad secret' });
      return;
    }
    // TODO Sprint 4:
    //  1. Validate payload shape (repoId / messageId / channelId / authorId /
    //     authorName / content / mentionedUserIds / timestamp)
    //  2. shouldKeepMessage() second-pass filter
    //  3. Idempotency via messageId (skip if exists)
    //  4. Write `repos/{repoId}/discordMessages/{messageId}` (no embedding here)
    logger.info('discordMessageIngest hit (skeleton)');
    res.status(200).send({ ok: true, note: 'discordMessageIngest is a stub' });
  },
);
