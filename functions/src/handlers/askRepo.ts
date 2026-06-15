import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';
import { openaiKey } from '../config';
import { askRepoFlow, type AskRepoTurn } from '../flows/askRepo';

// runId is a client-generated agent-trace doc id; validate its shape so it can
// never inject a path (the flow writes `agentRuns/{runId}`). Mirrors the guard
// in tools/agentTrace.ts.
const RUNID_RE = /^[A-Za-z0-9_-]{1,200}$/;

export const askRepo = onCall(
  // 512 MiB: the agentic loop + tool results pushed the default 256 MiB over
  // the limit (OOM kills surfaced as a generic failure to the client).
  { region: REGION, secrets: [openaiKey], timeoutSeconds: 120, memory: '512MiB' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { repoId, question, history, runId, language } = request.data as {
      repoId?: string;
      question?: string;
      history?: AskRepoTurn[];
      runId?: string;
      language?: string;
    };
    if (!repoId || !question || !question.trim()) {
      throw new HttpsError(
        'invalid-argument',
        'repoId and a non-empty question are required',
      );
    }
    if (runId !== undefined && !RUNID_RE.test(runId)) {
      throw new HttpsError('invalid-argument', 'runId has an invalid format');
    }
    // W6: optional language (a human-readable English language NAME the client
    // derives from the app locale) forces the answer into that language; absent
    // → unchanged behavior (the model mirrors the input language).
    if (language !== undefined && typeof language !== 'string') {
      throw new HttpsError('invalid-argument', 'language must be a string');
    }
    return askRepoFlow({
      repoId,
      question: question.trim(),
      history: Array.isArray(history) ? history : [],
      runId,
      language,
    });
  },
);
