// claimDiscordFetch (onRequest, secret-auth) — the always-on bot polls this to
// claim the oldest pending fetch request. Atomically flips it to `claimed` and
// returns the repo's Discord channel ids so the bot can REST-backfill the day.
// Mirrors discordMessageIngest's shared-secret auth. See ARCHITECTURE.md §7.
import { onRequest } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';

import { db, REGION } from '../admin';
import { discordIngestSecret } from '../config';

export const claimDiscordFetch = onRequest(
  { region: REGION, secrets: [discordIngestSecret], maxInstances: 10 },
  async (req, res) => {
    if (req.header('x-ingest-secret') !== discordIngestSecret.value()) {
      res.status(401).send({ error: 'bad secret' });
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).send({ error: 'method not allowed' });
      return;
    }

    // Optional repo filter; otherwise scan all repos via a collectionGroup.
    const body = (req.body ?? {}) as { repoId?: string };
    const repoId = typeof body.repoId === 'string' ? body.repoId : undefined;

    // 1. Find the oldest pending request (outside the transaction; the txn
    //    re-reads and guards the status to avoid a double-claim race).
    const baseQuery = repoId
      ? db.collection(`apps/gitsync/repos/${repoId}/fetchRequests`)
      : db.collectionGroup('fetchRequests');
    const pendingSnap = await baseQuery
      .where('status', '==', 'pending')
      .orderBy('createdAt', 'asc')
      .limit(1)
      .get();

    if (pendingSnap.empty) {
      res.status(200).send({ none: true });
      return;
    }

    const reqRef = pendingSnap.docs[0].ref;

    // 2. Claim it in a transaction (guard against a concurrent poller).
    const claimed = await db.runTransaction(async (txn) => {
      const fresh = await txn.get(reqRef);
      const data = fresh.data();
      if (!fresh.exists || !data || data.status !== 'pending') {
        return null; // someone else claimed it first
      }
      txn.update(reqRef, {
        status: 'claimed',
        claimedAt: FieldValue.serverTimestamp(),
      });
      return { requestId: fresh.id, repoId: data.repoId as string, date: data.date as string };
    });

    if (!claimed) {
      // Lost the race — tell the bot to poll again.
      res.status(200).send({ none: true });
      return;
    }

    // 3. Look up the repo's configured channels.
    const repoSnap = await db.doc(`apps/gitsync/repos/${claimed.repoId}`).get();
    const channelIds =
      (repoSnap.data()?.discordChannelIds as string[] | undefined) ?? [];

    logger.info('claimDiscordFetch claimed request', {
      requestId: claimed.requestId,
      repoId: claimed.repoId,
      date: claimed.date,
    });
    res.status(200).send({
      requestId: claimed.requestId,
      repoId: claimed.repoId,
      date: claimed.date,
      channelIds,
    });
  },
);
