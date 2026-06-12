import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { generateHandoffFlow } from '../flows/generateHandoff';

export const generateHandoff = onCall(
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 300 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, taskId, runId } = request.data as {
      repoId?: string;
      taskId?: string;
      runId?: string;
    };
    if (!repoId || !taskId) {
      throw new HttpsError(
        'invalid-argument',
        'repoId and taskId are required',
      );
    }
    if (runId !== undefined && !/^[A-Za-z0-9_-]{1,200}$/.test(runId)) {
      throw new HttpsError('invalid-argument', 'runId has an invalid format');
    }
    // Manual invocation (the "Regenerate handoff" button) always produces a
    // fresh doc; the auto trigger (onTaskUpdated) calls the flow with force=false
    // so it only fills in a missing handoff. `runId` (optional) streams the
    // live agent trace; absent → the trace is a no-op.
    return generateHandoffFlow({ repoId, taskId, force: true, runId });
  },
);
