import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { summarizeDayFlow } from '../flows/summarizeDay';

export const summarizeDay = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 180 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, date } = request.data as {
      repoId?: string;
      date?: string;
    };
    if (!repoId || !date) {
      throw new HttpsError(
        'invalid-argument',
        'repoId and date (YYYY-MM-DD) are required',
      );
    }
    return summarizeDayFlow({ repoId, date });
  },
);
