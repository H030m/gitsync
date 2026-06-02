// On-demand backfill poller.
//
// The bot has no public URL and no Firestore credentials, so it polls the
// secret-auth `claimDiscordFetch` function (~every pollIntervalMs). When a
// request is claimed, it REST-backfills that day's messages for each of the
// repo's configured channels, runs the shared noise filter, POSTs survivors to
// discordMessageIngest, then signals `completeDiscordFetch`. One failing channel
// or request must not kill the loop — failures are logged and the loop continues.
// See ARCHITECTURE.md §7.
import {
  ChannelType,
  type Client,
  type Message,
  type TextBasedChannel,
} from 'discord.js';

import type { BotConfig } from './config';
import { shouldKeepMessage } from './filter';
import { sendWithRetry, type IngestPayload } from './ingest';

// Taipei is a fixed UTC+8 offset year-round (matches discordDailyDigestFlow).
const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000;
const DISCORD_FETCH_LIMIT = 100; // max messages per REST page

interface ClaimResponse {
  none?: boolean;
  requestId?: string;
  repoId?: string;
  date?: string;
  channelIds?: string[];
}

// Returns [startMs, endMs) in epoch millis for the given Asia/Taipei calendar
// day. Mirrors taipeiDayBounds in functions/src/flows/discordDailyDigest.ts.
function taipeiDayBounds(date: string): { startMs: number; endMs: number } {
  const utcMidnight = new Date(`${date}T00:00:00Z`).getTime();
  if (Number.isNaN(utcMidnight)) {
    throw new Error(`invalid date: ${date}`);
  }
  const startMs = utcMidnight - TAIPEI_OFFSET_MS;
  return { startMs, endMs: startMs + 24 * 60 * 60 * 1000 };
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

// Fetches every message in a channel within [startMs, endMs), paginating
// backwards via the `before` cursor and stopping once messages are older than
// the day's start. Returns the in-window messages (any order).
async function fetchDayMessages(
  channel: TextBasedChannel,
  startMs: number,
  endMs: number,
): Promise<Message[]> {
  const collected: Message[] = [];
  let before: string | undefined;

  for (;;) {
    const batch = await channel.messages.fetch({
      limit: DISCORD_FETCH_LIMIT,
      ...(before ? { before } : {}),
    });
    if (batch.size === 0) break;

    let reachedOlderThanDay = false;
    for (const msg of batch.values()) {
      const ts = msg.createdTimestamp;
      if (ts < startMs) {
        // Messages come newest-first; once we cross the day start we're done.
        reachedOlderThanDay = true;
        continue;
      }
      if (ts < endMs) {
        collected.push(msg);
      }
      // ts >= endMs (newer than the day) → skip, keep paginating back.
    }

    if (reachedOlderThanDay) break;
    // Oldest message in this batch becomes the next cursor.
    before = batch.last()?.id;
    if (!before) break;
  }

  return collected;
}

// Processes one claimed fetch request: backfills all its channels, POSTs
// survivors, and reports completion. Errors are logged; never throws.
async function processRequest(client: Client, cfg: BotConfig, claim: ClaimResponse): Promise<void> {
  const { requestId, repoId, date, channelIds } = claim;
  if (!requestId || !repoId || !date) {
    console.error('[backfill] malformed claim response, skipping', claim);
    return;
  }
  const ids = channelIds ?? [];
  console.log(`[backfill] claimed ${requestId} repo=${repoId} date=${date} channels=${ids.length}`);

  let bounds: { startMs: number; endMs: number };
  try {
    bounds = taipeiDayBounds(date);
  } catch (e) {
    console.error(`[backfill] bad date for ${requestId}: ${String(e)}`);
    await reportComplete(cfg, repoId, requestId, 0);
    return;
  }

  let ingestedCount = 0;
  for (const channelId of ids) {
    try {
      const channel = await client.channels.fetch(channelId);
      if (
        !channel ||
        !channel.isTextBased() ||
        channel.type === ChannelType.DM ||
        channel.type === ChannelType.GroupDM
      ) {
        console.warn(`[backfill] channel ${channelId} not a guild text channel, skipping`);
        continue;
      }

      const messages = await fetchDayMessages(channel, bounds.startMs, bounds.endMs);
      for (const msg of messages) {
        if (
          !shouldKeepMessage({
            isBot: msg.author.bot,
            content: msg.content,
            attachmentCount: msg.attachments.size,
          })
        ) {
          continue;
        }
        const payload: IngestPayload = {
          repoId,
          messageId: msg.id,
          channelId: msg.channelId,
          authorId: msg.author.id,
          authorName: msg.author.username,
          content: msg.content,
          mentionedUserIds: [...msg.mentions.users.keys()],
          timestamp: msg.createdAt.toISOString(),
        };
        const ok = await sendWithRetry(cfg, payload);
        if (ok) ingestedCount++;
      }
    } catch (e) {
      // One failing channel must not abort the whole request.
      console.error(`[backfill] channel ${channelId} failed: ${String(e)}`);
    }
  }

  console.log(`[backfill] request ${requestId} ingested ${ingestedCount} message(s)`);
  await reportComplete(cfg, repoId, requestId, ingestedCount);
}

// POSTs completion to completeDiscordFetch. Logged-only on failure.
async function reportComplete(
  cfg: BotConfig,
  repoId: string,
  requestId: string,
  ingestedCount: number,
): Promise<void> {
  try {
    const res = await fetch(cfg.completeUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-ingest-secret': cfg.ingestSecret,
      },
      body: JSON.stringify({ repoId, requestId, ingestedCount }),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      console.error(`[backfill] completeDiscordFetch ${requestId} HTTP ${res.status}`);
    }
  } catch (e) {
    console.error(`[backfill] completeDiscordFetch ${requestId} failed: ${String(e)}`);
  }
}

// Polls claimDiscordFetch once. Returns true if a request was claimed and
// processed (so the caller can poll again immediately rather than waiting).
async function pollOnce(client: Client, cfg: BotConfig): Promise<boolean> {
  let claim: ClaimResponse;
  try {
    const res = await fetch(cfg.claimUrl, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'x-ingest-secret': cfg.ingestSecret,
      },
      body: JSON.stringify({}),
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) {
      console.error(`[backfill] claimDiscordFetch HTTP ${res.status}`);
      return false;
    }
    claim = (await res.json()) as ClaimResponse;
  } catch (e) {
    console.error(`[backfill] claimDiscordFetch failed: ${String(e)}`);
    return false;
  }

  if (claim.none) return false;
  await processRequest(client, cfg, claim);
  return true;
}

// Starts the never-ending poll loop. Runs in the background; never rejects.
export function startBackfillPoller(client: Client, cfg: BotConfig): void {
  console.log(`[backfill] poller started (interval ${cfg.pollIntervalMs}ms)`);
  void (async () => {
    for (;;) {
      let claimed = false;
      try {
        claimed = await pollOnce(client, cfg);
      } catch (e) {
        // Defensive: pollOnce already guards, but never let the loop die.
        console.error(`[backfill] poll loop error: ${String(e)}`);
      }
      // If we just processed a request there may be more queued — poll again
      // immediately; otherwise wait the configured interval.
      if (!claimed) await sleep(cfg.pollIntervalMs);
    }
  })();
}
