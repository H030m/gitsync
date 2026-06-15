// Observation search & active recall for the memory layer.
//
// Observations are short knowledge entries (1-3 sentences) stored at
// `repos/{repoId}/observations/{autoId}` with a 1536-dim embedding for
// semantic search. This module provides:
//   - `searchObservations()`: vector-first + keyword fallback search
//     (mirrors the `searchPastCommits` pattern in `tools/dailyIntel.ts`)
//   - `recallForPrompt()`: a higher-level helper that searches, deduplicates
//     against the project brief, and formats results as a prompt block.
//
// BEST-EFFORT throughout — every function tolerates failure (logger.warn)
// and NEVER throws, so it can never fail the host flow (Rule D).
import { logger } from 'firebase-functions/v2';

import { db } from '../admin';
import { embed } from './embedding';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface Observation {
  id: string;
  content: string;
  category: string;
  sourceFlow: string;
  sourceId: string | null;
  tags: string[];
  promoted: boolean;
  createdAt: string | null; // ISO 8601
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const KEYWORD_SCAN_LIMIT = 200;
const DEFAULT_LIMIT = 5;
const MAX_LIMIT = 15;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Lowercase word tokens of length >= 2. */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length >= 2);
}

function toObservation(id: string, data: Record<string, unknown>): Observation {
  return {
    id,
    content: (data.content as string | undefined) ?? '',
    category: (data.category as string | undefined) ?? '',
    sourceFlow: (data.sourceFlow as string | undefined) ?? '',
    sourceId: (data.sourceId as string | undefined) ?? null,
    tags: (data.tags as string[] | undefined) ?? [],
    promoted: (data.promoted as boolean | undefined) ?? false,
    createdAt: toIso(data.createdAt),
  };
}

function toIso(value: unknown): string | null {
  if (!value) return null;
  if (typeof value === 'string') return value;
  if (typeof (value as { toDate?: unknown }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString();
  }
  return null;
}

function obsCol(repoId: string) {
  return db.collection(`apps/gitsync/repos/${repoId}/observations`);
}

// ---------------------------------------------------------------------------
// searchObservations — vector-first + keyword fallback
// ---------------------------------------------------------------------------

/**
 * Search observations for a repo. VECTOR-FIRST: embed the query and run
 * `findNearest` on the observations collection (repoId prefilter, COSINE).
 * Falls back to keyword matching over the latest {@link KEYWORD_SCAN_LIMIT}
 * observations on an empty query, embedding failure, or zero vector hits.
 * Best-effort → [].
 */
export async function searchObservations(
  repoId: string,
  query: string,
  limit = DEFAULT_LIMIT,
): Promise<Observation[]> {
  const cap = Math.max(1, Math.min(limit, MAX_LIMIT));

  // ---- Vector-first path ---------------------------------------------------
  const terms = new Set(tokenize(query));
  if (terms.size > 0) {
    try {
      const queryVector = await embed(query);
      const snap = await obsCol(repoId)
        .where('repoId', '==', repoId)
        .findNearest({
          vectorField: 'embedding',
          queryVector,
          limit: cap,
          distanceMeasure: 'COSINE',
        })
        .get();
      if (!snap.empty) {
        return snap.docs.map((d) => toObservation(d.id, d.data() ?? {}));
      }
      // 0 hits → fall through to keyword path.
    } catch (err) {
      logger.warn('searchObservations: vector path unavailable (keyword fallback)', {
        repoId,
        err: String(err),
      });
    }
  }

  // ---- Keyword + recency fallback ------------------------------------------
  try {
    const snap = await obsCol(repoId)
      .orderBy('createdAt', 'desc')
      .limit(KEYWORD_SCAN_LIMIT)
      .get();
    const observations = snap.docs.map((d) => toObservation(d.id, d.data() ?? {}));

    if (terms.size === 0) return observations.slice(0, cap);

    const scored = observations
      .map((o) => {
        const hay = `${o.content} ${o.tags.join(' ')}`.toLowerCase();
        let score = 0;
        for (const t of terms) if (hay.includes(t)) score++;
        return { o, score };
      })
      .filter((s) => s.score > 0)
      .sort((a, b) => b.score - a.score);

    return (scored.length ? scored.map((s) => s.o) : observations).slice(0, cap);
  } catch (err) {
    logger.warn('searchObservations failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

// ---------------------------------------------------------------------------
// recallForPrompt — active recall formatted for system prompt injection
// ---------------------------------------------------------------------------

/**
 * Search observations and format them as a prompt block. Deduplicates against
 * the project brief content (observations already promoted into the brief are
 * skipped). Returns `''` on failure or no results — byte-identical to an
 * absent memory, so callers can unconditionally concatenate the result.
 *
 * Intended usage:
 * ```
 * const memoryContext = await recallForPrompt(repoId, { query, briefContent });
 * // append to system: briefPrefix + planGuidance + memoryContext
 * ```
 */
export async function recallForPrompt(
  repoId: string,
  opts: {
    query: string;
    limit?: number;
    /** The current project brief content (for dedup). */
    briefContent?: string;
  },
): Promise<string> {
  try {
    const hits = await searchObservations(repoId, opts.query, opts.limit ?? DEFAULT_LIMIT);
    if (hits.length === 0) return '';

    // Deduplicate: skip observations whose content already appears in the brief.
    const brief = (opts.briefContent ?? '').toLowerCase();
    const unique = brief
      ? hits.filter((o) => !brief.includes(o.content.toLowerCase().trim()))
      : hits;

    if (unique.length === 0) return '';

    const bullets = unique.map((o) => `- [${o.category}] ${o.content}`).join('\n');
    return `\n## Relevant memory\n${bullets}\n`;
  } catch (err) {
    logger.warn('recallForPrompt failed; returning empty (best-effort)', {
      repoId,
      err: String(err),
    });
    return '';
  }
}
