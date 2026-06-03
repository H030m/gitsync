import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { explainCommitFlow } from '../flows/explainCommit';

// explainCommit — the commit tree map's "tap a commit, AI explains the work"
// callable. Cached on the commit doc; pass force=true to regenerate.
export const explainCommit = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, sha, force } = request.data as {
      repoId?: string;
      sha?: string;
      force?: boolean;
    };
    if (!repoId || !sha) {
      throw new HttpsError('invalid-argument', 'repoId and sha are required');
    }
    return explainCommitFlow({ repoId, sha, force: force === true });
  },
);
