// addRepo (callable) — parses a GitHub URL, verifies the user's access via
// GitHub API, registers a webhook on the repo, and creates the matching
// Firestore docs (`repos/{repoId}` + `users/{uid}/repos/{repoId}`).
//
// See ARCHITECTURE.md §6.2 for the full flow.
import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { REGION } from '../admin';

export const addRepo = onCall(
  { region: REGION },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const { githubUrl } = request.data as { githubUrl?: string };
    if (!githubUrl) {
      throw new HttpsError('invalid-argument', 'githubUrl is required');
    }
    // TODO Sprint 1:
    //  1. Parse githubUrl → { owner, repo }
    //  2. Look up the user's stored githubAccessToken
    //  3. Verify the repo exists and the user has write access via Octokit
    //  4. Register a webhook (POST /repos/{owner}/{repo}/hooks) with a
    //     random secret stored on `repos/{repoId}.webhookSecret`
    //  5. Write `apps/gitsync/repos/{repoId}` + `users/{uid}/repos/{repoId}`
    throw new HttpsError('unimplemented', 'addRepo not implemented yet');
  },
);
