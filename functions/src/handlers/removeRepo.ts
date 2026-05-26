// removeRepo (callable) — deletes the GitHub webhook + Firestore docs.
import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';

export const removeRepo = onCall(
  { region: REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId } = request.data as { repoId?: string };
    if (!repoId) {
      throw new HttpsError('invalid-argument', 'repoId is required');
    }
    // TODO Sprint 1: verify caller is owner, delete webhook, delete Firestore docs.
    throw new HttpsError('unimplemented', 'removeRepo not implemented yet');
  },
);
