// Loads + validates environment config for the GitSync bot.
//
// The bot has no Firestore credentials — it only talks to Cloud Functions over
// HTTP with the shared `x-ingest-secret`. Channel→repo mapping now lives in
// Firestore (set via /gitsync-listen → setRepoChannel) and is fetched at
// backfill time via claimDiscordFetch, so there is no static CHANNEL_REPO_MAP.
import 'dotenv/config';

export interface BotConfig {
  botToken: string;
  ingestSecret: string;
  // Cloud Function endpoints (all secret-auth onRequest, same asia-east1 base).
  ingestUrl: string; // discordMessageIngest
  claimUrl: string; // claimDiscordFetch
  completeUrl: string; // completeDiscordFetch
  setRepoChannelUrl: string; // setRepoChannel
  // Backfill poll interval in milliseconds.
  pollIntervalMs: number;
}

function required(name: string): string {
  const value = process.env[name];
  if (!value || value === 'REPLACE_ME') {
    throw new Error(`Missing required env var: ${name} (see .env.example)`);
  }
  return value;
}

const DEFAULT_POLL_INTERVAL_MS = 5000;

export function loadConfig(): BotConfig {
  // FUNCTIONS_BASE_URL is the deployment base; per-endpoint URLs are derived by
  // appending the function name (matches the asia-east1 onRequest URL layout).
  const baseUrl = required('FUNCTIONS_BASE_URL').replace(/\/+$/, '');
  const endpoint = (name: string) => `${baseUrl}/${name}`;

  const rawInterval = process.env.POLL_INTERVAL_MS;
  const parsedInterval = rawInterval ? Number(rawInterval) : NaN;
  const pollIntervalMs =
    Number.isFinite(parsedInterval) && parsedInterval > 0
      ? parsedInterval
      : DEFAULT_POLL_INTERVAL_MS;

  return {
    botToken: required('DISCORD_BOT_TOKEN'),
    ingestSecret: required('DISCORD_INGEST_SECRET'),
    ingestUrl: endpoint('discordMessageIngest'),
    claimUrl: endpoint('claimDiscordFetch'),
    completeUrl: endpoint('completeDiscordFetch'),
    setRepoChannelUrl: endpoint('setRepoChannel'),
    pollIntervalMs,
  };
}
