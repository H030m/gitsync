import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { editDiscordDigestFlow } from '../flows/editDiscordDigest';

// editDiscordDigest (onCall) — the app's "ask AI to adjust this summary" field.
// Rewrites the digest for {repoId, date} per the instruction. Refuses if the
// digest is locked (HttpsError failed-precondition propagates to the client).
export const editDiscordDigest = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, date, instruction } = request.data as {
      repoId?: string;
      date?: string;
      instruction?: string;
    };
    if (!repoId || !date || !instruction || !instruction.trim()) {
      throw new HttpsError(
        'invalid-argument',
        'repoId, date and a non-empty instruction are required',
      );
    }
    return editDiscordDigestFlow({
      repoId,
      date,
      instruction: instruction.trim(),
    });
  },
);
