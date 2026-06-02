// Loads + validates environment config for the forwarder bot.
import 'dotenv/config';

export interface BotConfig {
  botToken: string;
  ingestSecret: string;
  ingestUrl: string;
  channelRepoMap: Map<string, string>; // channelId -> repoId
}

function required(name: string): string {
  const value = process.env[name];
  if (!value || value === 'REPLACE_ME') {
    throw new Error(`Missing required env var: ${name} (see .env.example)`);
  }
  return value;
}

// Parses "id1:repo1,id2:repo2" into a Map. Malformed entries are skipped.
function parseChannelRepoMap(raw: string): Map<string, string> {
  const map = new Map<string, string>();
  for (const pair of raw.split(',')) {
    const trimmed = pair.trim();
    if (!trimmed) continue;
    const idx = trimmed.indexOf(':');
    if (idx <= 0 || idx === trimmed.length - 1) {
      console.warn(`[config] ignoring malformed CHANNEL_REPO_MAP entry: "${trimmed}"`);
      continue;
    }
    map.set(trimmed.slice(0, idx).trim(), trimmed.slice(idx + 1).trim());
  }
  return map;
}

export function loadConfig(): BotConfig {
  const channelRepoMap = parseChannelRepoMap(required('CHANNEL_REPO_MAP'));
  if (channelRepoMap.size === 0) {
    throw new Error('CHANNEL_REPO_MAP has no valid channelId:repoId entries');
  }
  return {
    botToken: required('DISCORD_BOT_TOKEN'),
    ingestSecret: required('DISCORD_INGEST_SECRET'),
    ingestUrl: required('INGEST_URL'),
    channelRepoMap,
  };
}
