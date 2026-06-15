// OpenAI client + secret declarations.
//
// `defineSecret` registers a secret with Firebase. To make a callable / trigger
// receive the value at runtime, list the secret in its `secrets:` option (e.g.
// `onCall({ region: REGION, secrets: [openaiKey] }, handler)`).
//
// Local emulator picks up secrets from `functions/.secret.local`.
// Production reads them from Google Secret Manager.
import { defineSecret } from 'firebase-functions/params';
import OpenAI from 'openai';

export const openaiKey = defineSecret('OPENAI_API_KEY');
export const discordIngestSecret = defineSecret('DISCORD_INGEST_SECRET');
// GitHub OAuth App client secret — used by `exchangeGitHubCode` to swap an
// authorization code for a user access token. Set once with:
//   firebase functions:secrets:set GITHUB_OAUTH_CLIENT_SECRET
// NEVER ships in the Flutter APK; only the (public) client_id does.
export const githubOAuthClientSecret = defineSecret(
  'GITHUB_OAUTH_CLIENT_SECRET',
);

// The GitHub OAuth App client_id is public (it travels in the authorize URL the
// app opens) so it lives in code, not a secret. Overridable via the
// GITHUB_OAUTH_CLIENT_ID env var for a different OAuth App without a code change.
// The Flutter client sends the SAME id in its authorize URL — keep them in sync
// with the GitHub OAuth App you registered (see the task PRD Technical Notes).
export const GITHUB_OAUTH_CLIENT_ID =
  process.env.GITHUB_OAUTH_CLIENT_ID ?? 'Ov23liGitSyncClientId';

let _openai: OpenAI | null = null;

export function getOpenAI(): OpenAI {
  if (_openai) return _openai;
  _openai = new OpenAI({ apiKey: openaiKey.value() });
  return _openai;
}

export const MODELS = {
  reasoning: 'gpt-4o',
  fast: 'gpt-4o-mini',
  embedding: 'text-embedding-3-small',
} as const;

export const EMBEDDING_DIM = 1536;
