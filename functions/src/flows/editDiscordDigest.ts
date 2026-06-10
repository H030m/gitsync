// editDiscordDigestFlow — AI-rewrites an existing Discord daily digest in place
// per a natural-language instruction. Shared by the app callable
// (`editDiscordDigest`) and the bot command bridge (`botEditDigest`).
//
// Lock semantics (ARCHITECTURE §7): a digest with `locked === true` is frozen —
// this flow refuses to edit it, and `discordDailyDigestFlow` refuses to
// regenerate it. The lock is the single gate every digest-write path checks.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import {
  editDiscordDigestSystem,
  editDiscordDigestUser,
} from '../prompts/editDiscordDigest';

// Taipei is a fixed UTC+8 offset year-round (matches discordDailyDigestFlow).
const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000;

export interface EditDiscordDigestInput {
  repoId: string;
  date: string; // YYYY-MM-DD
  instruction: string;
}

export interface EditDiscordDigestResult {
  date: string;
  markdown: string;
}

/** Today's date string (YYYY-MM-DD) in the Asia/Taipei timezone. */
export function taipeiTodayString(now: Date): string {
  const taipei = new Date(now.getTime() + TAIPEI_OFFSET_MS);
  return taipei.toISOString().slice(0, 10);
}

/**
 * Revise the digest at `discordDigests/{date}` per `instruction`. Throws an
 * HttpsError on a missing day (`not-found`) or a locked digest
 * (`failed-precondition`) — both callers translate that to a user-facing
 * message.
 */
export async function editDiscordDigestFlow(
  input: EditDiscordDigestInput,
): Promise<EditDiscordDigestResult> {
  const { repoId, date, instruction } = input;
  const ref = db.doc(`apps/gitsync/repos/${repoId}/discordDigests/${date}`);
  const snap = await ref.get();
  if (!snap.exists) {
    throw new HttpsError('not-found', `No digest for ${date} yet.`);
  }
  const data = snap.data() ?? {};
  if (data.locked === true) {
    throw new HttpsError('failed-precondition', 'This digest is locked.');
  }

  const current = (data.markdown as string | undefined) ?? '';
  logger.info('editDiscordDigestFlow: rewriting digest', { repoId, date });
  const completion = await getOpenAI().chat.completions.create({
    model: MODELS.fast,
    messages: [
      { role: 'system', content: editDiscordDigestSystem },
      { role: 'user', content: editDiscordDigestUser({ current, instruction }) },
    ],
  });
  const markdown = completion.choices[0]?.message?.content?.trim() || current;

  await ref.set(
    {
      markdown,
      editedAt: FieldValue.serverTimestamp(),
      lastEditInstruction: instruction,
    },
    { merge: true },
  );

  return { date, markdown };
}

/**
 * Resolve which repo a Discord channel is bound to. Returns the first repo
 * whose `discordChannelIds` array contains `channelId`, or null. Used by the
 * bot bridge, which only knows the channel it was invoked in.
 */
export async function repoIdForChannel(channelId: string): Promise<string | null> {
  const snap = await db
    .collection('apps/gitsync/repos')
    .where('discordChannelIds', 'array-contains', channelId)
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0].id;
}
