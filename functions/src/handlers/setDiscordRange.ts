// setDiscordRange (callable, auth) — the app's Daily → Discord range picker
// calls this to set the backfill window [startDate, endDate] for a repo. It:
//   1. persists the range on the repo doc (discordStartDate/discordEndDate) so
//      it survives re-login and pre-fills the picker,
//   2. resets each channel's watermark so the next backfill re-pulls the whole
//      new window (messageId dedup prevents duplicates),
//   3. PRUNES data now outside the window — deletes discordMessages whose
//      timestamp falls before the start or on/after the day after end, and
//      deletes discordDigests for days outside [start, end].
// See ARCHITECTURE.md §7 and prd.md (06-03-discord-range-cursor).
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions/v2';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { db, REGION } from '../admin';
import { taipeiDayStartMs } from '../tools/discordSnowflake';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ONE_DAY_MS = 24 * 60 * 60 * 1000;
const DELETE_CHUNK = 450; // stay under the 500-write batch limit

// Deletes every doc in `refs` in chunks. Returns the number deleted.
async function deleteAll(
  refs: FirebaseFirestore.DocumentReference[],
): Promise<number> {
  for (let i = 0; i < refs.length; i += DELETE_CHUNK) {
    const batch = db.batch();
    for (const ref of refs.slice(i, i + DELETE_CHUNK)) batch.delete(ref);
    await batch.commit();
  }
  return refs.length;
}

export const setDiscordRange = onCall({ region: REGION }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('failed-precondition', 'Please log in first.');
  }

  const { repoId, startDate, endDate } = request.data as {
    repoId?: string;
    startDate?: string;
    endDate?: string;
  };
  if (!repoId || typeof repoId !== 'string') {
    throw new HttpsError('invalid-argument', 'repoId is required');
  }
  if (!startDate || !DATE_RE.test(startDate) || !endDate || !DATE_RE.test(endDate)) {
    throw new HttpsError('invalid-argument', 'startDate/endDate must be YYYY-MM-DD');
  }
  if (startDate > endDate) {
    throw new HttpsError('invalid-argument', 'startDate must be <= endDate');
  }

  const repoRef = db.doc(`apps/gitsync/repos/${repoId}`);
  const [repoSnap, chanSnap] = await Promise.all([
    repoRef.get(),
    repoRef.collection('discordChannels').get(),
  ]);
  if (!repoSnap.exists) {
    throw new HttpsError('not-found', `repo ${repoId} not found`);
  }

  // 1. Persist the range on the repo doc (source of truth for the picker + bot).
  await repoRef.set(
    {
      discordStartDate: startDate,
      discordEndDate: endDate,
      discordRangeSetAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  // 2. Reset each channel's watermark so the next backfill re-pulls the window.
  const ids = new Set<string>([
    ...((repoSnap.data()?.discordChannelIds as string[] | undefined) ?? []),
    ...chanSnap.docs.map((d) => d.id),
  ]);
  if (ids.size > 0) {
    const batch = db.batch();
    for (const id of ids) {
      batch.set(
        repoRef.collection('discordChannels').doc(id),
        { startDate, lastMessageId: FieldValue.delete() },
        { merge: true },
      );
    }
    await batch.commit();
  }

  // 3a. Prune messages outside [startMs, endExclusiveMs). Two range queries
  //     (Firestore has no OR); collect refs then batch-delete.
  const startMs = taipeiDayStartMs(startDate);
  const endExclusiveMs = taipeiDayStartMs(endDate) + ONE_DAY_MS;
  const msgCol = repoRef.collection('discordMessages');
  const [beforeSnap, afterSnap] = await Promise.all([
    msgCol.where('timestamp', '<', Timestamp.fromMillis(startMs)).get(),
    msgCol.where('timestamp', '>=', Timestamp.fromMillis(endExclusiveMs)).get(),
  ]);
  const prunedMessages = await deleteAll([
    ...beforeSnap.docs.map((d) => d.ref),
    ...afterSnap.docs.map((d) => d.ref),
  ]);

  // 3b. Prune digests for days outside [startDate, endDate]. Digest doc ids are
  //     YYYY-MM-DD, which sort chronologically as strings.
  const digestSnap = await repoRef.collection('discordDigests').get();
  const prunedDigests = await deleteAll(
    digestSnap.docs
      .filter((d) => d.id < startDate || d.id > endDate)
      .map((d) => d.ref),
  );

  logger.info('setDiscordRange applied', {
    repoId,
    startDate,
    endDate,
    channelCount: ids.size,
    prunedMessages,
    prunedDigests,
  });

  return {
    ok: true,
    channelCount: ids.size,
    prunedMessages,
    prunedDigests,
  };
});
