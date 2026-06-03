// Reusable tool helper for discordChatFlow (ARCHITECTURE §7).
//
// `searchDiscordMessages` is the single data-access primitive the discord-chat
// agentic loop exposes to OpenAI as a function tool. It reads the repo's
// ingested Discord messages and ranks them against a natural-language query.
//
// IMPORTANT: Discord messages currently carry NO embedding vector
// (`onDiscordMessageCreated` is still a stub), so this is a keyword + recency
// ranker rather than a semantic search. It needs no vector index, which also
// means it runs unchanged against the fake backend's in-memory messages.
import { logger } from 'firebase-functions/v2';
import { db } from '../admin';

/** One Discord message as the chat agent (and the client UI) sees it. */
export interface DiscordMessageHit {
  messageId: string;
  channelId: string;
  authorName: string;
  content: string;
  timestamp: string | null; // ISO 8601, or null if missing
}

// How many recent messages we pull before ranking, and the hard cap on the
// number we ever hand back to the model / client.
const SCAN_LIMIT = 300;
const MAX_RETURN = 30;
const DEFAULT_RETURN = 12;

// How many day summaries `listDaySummaries` returns, and the preview length.
const MAX_DAY_SUMMARIES = 60;
const DAY_PREVIEW_CHARS = 180;

/** A per-day digest as the chat agent sees it in `listDaySummaries` (small). */
export interface DaySummaryHit {
  date: string; // YYYY-MM-DD
  messageCount: number;
  preview: string; // first ~180 chars of the day's markdown digest
}

/** A full day digest from `getDaySummary`. */
export interface DaySummary {
  date: string;
  messageCount: number;
  markdown: string;
}

/**
 * List the available per-day digests for a repo (newest first), each as a tiny
 * preview. This is the CHEAP first stop for summary / overview questions: the
 * agent scans dates + topics here (O(days) tokens) and only drills into a
 * specific day's full text via {@link getDaySummary}, instead of reading every
 * raw message. Never throws — degrades to [].
 */
export async function listDaySummaries(repoId: string): Promise<DaySummaryHit[]> {
  try {
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/discordDigests`)
      .orderBy('date', 'desc')
      .limit(MAX_DAY_SUMMARIES)
      .get();

    return snap.docs.map((d) => {
      const data = d.data() ?? {};
      const md = (data.markdown as string | undefined) ?? '';
      return {
        date: (data.date as string | undefined) ?? d.id,
        messageCount: (data.messageCount as number | undefined) ?? 0,
        preview: md.replace(/\s+/g, ' ').trim().slice(0, DAY_PREVIEW_CHARS),
      };
    });
  } catch (err) {
    logger.warn('listDaySummaries failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

/**
 * Full markdown digest for one day, or null if that day has no digest yet.
 * Never throws — degrades to null.
 */
export async function getDaySummary(
  repoId: string,
  date: string,
): Promise<DaySummary | null> {
  try {
    const doc = await db
      .doc(`apps/gitsync/repos/${repoId}/discordDigests/${date}`)
      .get();
    if (!doc.exists) return null;
    const data = doc.data() ?? {};
    return {
      date: (data.date as string | undefined) ?? date,
      messageCount: (data.messageCount as number | undefined) ?? 0,
      markdown: (data.markdown as string | undefined) ?? '',
    };
  } catch (err) {
    logger.warn('getDaySummary failed; returning null (best-effort)', {
      repoId,
      date,
      err: String(err),
    });
    return null;
  }
}

/** Lowercase word tokens of length >= 2 (drops punctuation + stopword-ish noise). */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length >= 2);
}

/**
 * Keyword + recency search over a repo's `discordMessages`. Pulls the most
 * recent {@link SCAN_LIMIT} messages, scores each by how many distinct query
 * tokens appear in its content, and returns the top `limit` by (score,
 * recency). When NO message matches any token (e.g. a vague question), it
 * degrades to the most recent `limit` messages so the agent always has
 * something to ground its answer on.
 *
 * Never throws — a Firestore read failure degrades to `[]` + a `logger.warn`,
 * so a single bad call can't kill the whole chat flow.
 */
export async function searchDiscordMessages(
  repoId: string,
  query: string,
  limit = DEFAULT_RETURN,
): Promise<DiscordMessageHit[]> {
  const cap = Math.max(1, Math.min(limit || DEFAULT_RETURN, MAX_RETURN));
  try {
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/discordMessages`)
      .orderBy('timestamp', 'desc')
      .limit(SCAN_LIMIT)
      .get();

    const docs = snap.docs.map((d) => {
      const data = d.data() ?? {};
      const ts = data.timestamp;
      return {
        messageId: d.id,
        channelId: (data.channelId as string | undefined) ?? '',
        authorName: (data.authorName as string | undefined) ?? '',
        content: (data.content as string | undefined) ?? '',
        // Firestore Timestamp → ISO; tolerate already-string / missing values.
        timestamp:
          ts && typeof (ts as { toDate?: unknown }).toDate === 'function'
            ? (ts as { toDate: () => Date }).toDate().toISOString()
            : typeof ts === 'string'
              ? ts
              : null,
      };
    });

    return rankMessages(docs, query, cap);
  } catch (err) {
    logger.warn('searchDiscordMessages failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

/**
 * Pure ranking core (no I/O) — extracted so it can be unit-tested directly.
 * `docs` is assumed to arrive newest-first (as Firestore returns them); ties in
 * score are broken by preserving that recency order.
 */
export function rankMessages(
  docs: DiscordMessageHit[],
  query: string,
  cap: number,
): DiscordMessageHit[] {
  const terms = new Set(tokenize(query));

  if (terms.size === 0) {
    // No usable query terms — just hand back the most recent slice.
    return docs.slice(0, cap);
  }

  const scored = docs.map((doc, index) => {
    const haystack = doc.content.toLowerCase();
    let score = 0;
    for (const term of terms) {
      if (haystack.includes(term)) score += 1;
    }
    return { doc, score, index };
  });

  const matched = scored
    .filter((s) => s.score > 0)
    .sort((a, b) => (b.score - a.score) || (a.index - b.index));

  if (matched.length === 0) {
    // Nothing matched — degrade to most-recent so the agent isn't empty-handed.
    return docs.slice(0, cap);
  }

  return matched.slice(0, cap).map((s) => s.doc);
}
