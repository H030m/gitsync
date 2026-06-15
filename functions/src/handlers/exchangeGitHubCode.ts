// exchangeGitHubCode (callable) — completes the manual GitHub OAuth
// authorization-code flow for clients that can't get the token from
// firebase_auth directly (Android `signInWithProvider` returns a base
// AuthCredential with a null accessToken — see task 06-16 research).
//
// The Flutter app runs the browser authorize step (`flutter_web_auth_2`),
// captures the `?code=...` redirect, then calls this callable. The
// client_secret-bearing exchange happens ONLY here (server side) so the secret
// never ships in the APK. The resulting `gho_` token is written to the same
// `users/{uid}.githubAccessToken` field every backend consumer already reads,
// so nothing else changes.
import { logger } from 'firebase-functions/v2';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

import { db, REGION } from '../admin';
import {
  GITHUB_OAUTH_CLIENT_ID,
  githubOAuthClientSecret,
} from '../config';
import { exchangeOAuthCode } from '../services/githubClient';

/** Scopes the app must end up with (matches authentication.dart's request). */
const REQUIRED_SCOPES = ['repo', 'read:user'];

export const exchangeGitHubCode = onCall(
  { region: REGION, secrets: [githubOAuthClientSecret], timeoutSeconds: 60 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('failed-precondition', 'Please log in first.');
    }
    const uid = request.auth.uid;

    const { code, redirectUri } = request.data as {
      code?: string;
      redirectUri?: string;
    };
    if (!code || typeof code !== 'string') {
      throw new HttpsError('invalid-argument', 'code is required');
    }
    if (!redirectUri || typeof redirectUri !== 'string') {
      throw new HttpsError('invalid-argument', 'redirectUri is required');
    }

    // ---- Swap the code for an access token (secret stays server-side) -------
    let result;
    try {
      result = await exchangeOAuthCode({
        clientId: GITHUB_OAUTH_CLIENT_ID,
        clientSecret: githubOAuthClientSecret.value(),
        code,
        redirectUri,
      });
    } catch (err) {
      // Never echo the raw error (no secret leaks anyway, but stay terse).
      logger.warn('exchangeGitHubCode: token exchange failed', {
        uid,
        err: String(err),
      });
      throw new HttpsError(
        'failed-precondition',
        'Could not complete GitHub authorization. Please try connecting again.',
      );
    }

    // ---- Verify the granted scopes cover what the app needs ----------------
    const granted = new Set(
      result.scope
        .split(/[\s,]+/)
        .map((s) => s.trim())
        .filter(Boolean),
    );
    const missing = REQUIRED_SCOPES.filter((s) => !granted.has(s));
    if (missing.length > 0) {
      logger.warn('exchangeGitHubCode: insufficient scopes', {
        uid,
        missing,
      });
      throw new HttpsError(
        'failed-precondition',
        `GitHub authorization is missing required scope(s): ${missing.join(', ')}. ` +
          'Please grant access and try again.',
      );
    }

    // ---- Persist to the same field every consumer reads --------------------
    // set+merge mirrors user_repo.upsertUserFromAuth so this overwrites a stale
    // token without disturbing the rest of the user doc.
    await db
      .doc(`apps/gitsync/users/${uid}`)
      .set({ githubAccessToken: result.accessToken }, { merge: true });

    // Deliberately NOT returning the token to the client.
    return { ok: true };
  },
);
