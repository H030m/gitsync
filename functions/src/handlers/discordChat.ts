import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { discordChatFlow, type ChatTurn } from '../flows/discordChat';

export const discordChat = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 120 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, question, history } = request.data as {
      repoId?: string;
      question?: string;
      history?: ChatTurn[];
    };
    if (!repoId || !question || !question.trim()) {
      throw new HttpsError(
        'invalid-argument',
        'repoId and a non-empty question are required',
      );
    }
    return discordChatFlow({
      repoId,
      question: question.trim(),
      history: Array.isArray(history) ? history : [],
    });
  },
);
