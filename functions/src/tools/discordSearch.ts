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
import type { Timestamp } from 'firebase-admin/firestore';
import { db } from '../admin';

/**
 * Inclusive Asia/Taipei day window the chat is scoped to. `start`/`end` are the
 * [startInclusive, endExclusive) Firestore Timestamps (from taipeiRangeBounds);
 * `startDate`/`endDate` are the YYYY-MM-DD keys for filtering digest doc ids.
 */
export interface SearchRange {
  start: Timestamp;
  end: Timestamp;
  startDate: string;
  endDate: string;
}

/** One Discord message as the chat agent (and the client UI) sees it. */
export interface DiscordMessageHit {
  messageId: string;
  channelId: string;
  authorName: string;
  content: string;
  timestamp: string | null; // ISO 8601, or null if missing
  isMatch: boolean; // true if it matched the query (vs. surrounding context)
}

// How many recent messages we pull before grouping into snippets.
const SCAN_LIMIT = 300;

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
 * raw message. When `range` is given, only digests for days within
 * [startDate, endDate] (inclusive) are returned. Never throws — degrades to [].
 */
export async function listDaySummaries(
  repoId: string,
  range?: SearchRange,
): Promise<DaySummaryHit[]> {
  try {
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/discordDigests`)
      .orderBy('date', 'desc')
      .limit(MAX_DAY_SUMMARIES)
      .get();

    return snap.docs
      .filter((d) => {
        if (!range) return true;
        // Digest doc ids (and `date` fields) are YYYY-MM-DD → lexicographic
        // comparison equals chronological; restrict to the active window.
        const key = ((d.data()?.date as string | undefined) ?? d.id);
        return key >= range.startDate && key <= range.endDate;
      })
      .map((d) => {
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

/** How many messages of context to include before/after each matched message. */
const CONTEXT_BEFORE = 2;
const CONTEXT_AFTER = 2;
const DEFAULT_SNIPPETS = 6;
const MAX_SNIPPETS = 12;

/**
 * A conversation snippet: a run of chronologically-ordered messages from ONE
 * channel, centered on the message(s) that matched the query (`isMatch: true`)
 * with a few surrounding messages for context. This is what the chat agent and
 * the UI panel consume — grouped clusters, NOT a flat dump.
 */
export interface DiscordSnippet {
  channelId: string;
  messages: DiscordMessageHit[]; // oldest → newest, context + matches
  score: number; // number of matched messages (for ranking)
}

/** Lowercase word tokens of length >= 2 (drops punctuation + stopword-ish noise). */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length >= 2);
}

/** -1 / 0 / 1 comparison of two snowflake id strings by BigInt value. */
function cmpId(a: string, b: string): number {
  const x = BigInt(a || '0');
  const y = BigInt(b || '0');
  return x < y ? -1 : x > y ? 1 : 0;
}

/**
 * Keyword search over a repo's `discordMessages`, returning grouped conversation
 * snippets (each matched message bundled with {@link CONTEXT_BEFORE}/
 * {@link CONTEXT_AFTER} surrounding messages from the same channel; overlapping
 * windows merge). Snippets are ranked by match count then recency. When nothing
 * matches, degrades to one snippet of the most recent messages.
 *
 * When `range` is given, the scan is restricted to messages whose `timestamp`
 * falls in [start, end) (same field as the orderBy → no composite index).
 *
 * Never throws — a Firestore read failure degrades to `[]` + a `logger.warn`.
 */
export async function searchDiscordMessages(
  repoId: string,
  query: string,
  limit = DEFAULT_SNIPPETS,
  range?: SearchRange,
): Promise<DiscordSnippet[]> {
  try {
    let q: FirebaseFirestore.Query = db.collection(
      `apps/gitsync/repos/${repoId}/discordMessages`,
    );
    if (range) {
      q = q
        .where('timestamp', '>=', range.start)
        .where('timestamp', '<', range.end);
    }
    const snap = await q
      .orderBy('timestamp', 'desc')
      .limit(SCAN_LIMIT)
      .get();

    const docs: DiscordMessageHit[] = snap.docs.map((d) => {
      const data = d.data() ?? {};
      const ts = data.timestamp;
      return {
        messageId: d.id,
        channelId: (data.channelId as string | undefined) ?? '',
        authorName: (data.authorName as string | undefined) ?? '',
        content: (data.content as string | undefined) ?? '',
        isMatch: false,
        // Firestore Timestamp → ISO; tolerate already-string / missing values.
        timestamp:
          ts && typeof (ts as { toDate?: unknown }).toDate === 'function'
            ? (ts as { toDate: () => Date }).toDate().toISOString()
            : typeof ts === 'string'
              ? ts
              : null,
      };
    });

    return buildSnippets(docs, query, { maxSnippets: limit });
  } catch (err) {
    logger.warn('searchDiscordMessages failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

/**
 * Pure snippet builder (no I/O) — extracted for unit tests. Groups matched
 * messages with surrounding context, per channel, merging overlapping windows.
 * `docs` may arrive in any order; they are re-sorted by snowflake id per
 * channel. When the query has no usable terms OR nothing matches, returns a
 * single snippet of the most recent messages (so the agent isn't empty-handed).
 */
export function buildSnippets(
  docs: DiscordMessageHit[],
  query: string,
  opts?: { before?: number; after?: number; maxSnippets?: number },
): DiscordSnippet[] {
  const before = opts?.before ?? CONTEXT_BEFORE;
  const after = opts?.after ?? CONTEXT_AFTER;
  const maxSnippets = Math.max(1, Math.min(opts?.maxSnippets ?? DEFAULT_SNIPPETS, MAX_SNIPPETS));
  const terms = new Set(tokenize(query));

  const recentFallback = (): DiscordSnippet[] => {
    const recent = [...docs]
      .sort((a, b) => cmpId(b.messageId, a.messageId))
      .slice(0, before + after + 1)
      .sort((a, b) => cmpId(a.messageId, b.messageId))
      .map((m) => ({ ...m, isMatch: false }));
    return recent.length
      ? [{ channelId: recent[0].channelId, messages: recent, score: 0 }]
      : [];
  };

  if (terms.size === 0) return recentFallback();

  const matches = (content: string): boolean => {
    const hay = content.toLowerCase();
    for (const t of terms) if (hay.includes(t)) return true;
    return false;
  };

  // Group by channel, sort each channel chronologically (by snowflake id).
  const byChannel = new Map<string, DiscordMessageHit[]>();
  for (const d of docs) {
    const arr = byChannel.get(d.channelId);
    if (arr) arr.push(d);
    else byChannel.set(d.channelId, [d]);
  }

  const snippets: DiscordSnippet[] = [];
  for (const [channelId, arrRaw] of byChannel) {
    const arr = [...arrRaw].sort((a, b) => cmpId(a.messageId, b.messageId));
    const hit = arr.map((m) => matches(m.content));

    // Merge each hit's [k-before, k+after] window into contiguous ranges.
    const ranges: Array<[number, number]> = [];
    for (let k = 0; k < arr.length; k++) {
      if (!hit[k]) continue;
      const lo = Math.max(0, k - before);
      const hi = Math.min(arr.length - 1, k + after);
      const last = ranges[ranges.length - 1];
      if (last && lo <= last[1] + 1) last[1] = Math.max(last[1], hi);
      else ranges.push([lo, hi]);
    }

    for (const [lo, hi] of ranges) {
      const messages = arr
        .slice(lo, hi + 1)
        .map((m, idx) => ({ ...m, isMatch: hit[lo + idx] }));
      snippets.push({
        channelId,
        messages,
        score: messages.filter((m) => m.isMatch).length,
      });
    }
  }

  if (snippets.length === 0) return recentFallback();

  // Rank: more matches first, then most-recent (by the snippet's newest id).
  const lastId = (s: DiscordSnippet) => s.messages[s.messages.length - 1].messageId;
  snippets.sort((a, b) => b.score - a.score || cmpId(lastId(b), lastId(a)));
  return snippets.slice(0, maxSnippets);
}
