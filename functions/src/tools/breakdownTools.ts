// Read-only, repo-scoped tools for the INCREMENTAL breakdown agentic loop
// (flows/breakdownTask.ts). The agent uses these to explore the repo's EXISTING
// tasks on demand — paginated / limited — instead of the flow dumping the whole
// task list into the prompt (prd D5: context must not grow with task count).
//
// Every path is `apps/gitsync/repos/{repoId}/tasks/...`, so reads are naturally
// repo-isolated (prd D2 / requirement 8). To keep the prompt cheap we return
// only the minimal fields needed for dedup + DAG wiring (prd D4):
//   - listExistingTaskTitles → {taskId, title, status}
//   - searchExistingTasks    → {taskId, title, status, dependsOn}
import { logger } from 'firebase-functions/v2';

import { db } from '../admin';

/** Minimal existing-task summary for the listing tool (prd D4 — no description). */
export interface ExistingTaskSummary {
  taskId: string;
  title: string;
  status: string;
}

/** Summary + stored dependsOn, used by search (so the model can wire the DAG). */
export interface ExistingTaskWithDeps extends ExistingTaskSummary {
  dependsOn: string[];
}

/** One page of {@link listExistingTaskTitles}. */
export interface ExistingTaskPage {
  tasks: ExistingTaskSummary[];
  /** Cursor for the next page (the last taskId), or null when no more. */
  nextCursor: string | null;
}

/** Page size for listExistingTaskTitles — small so a big repo never floods the
 *  prompt (the model pages via `cursor` if it wants more). */
export const TITLES_PAGE_SIZE = 25;
/** Default / hard caps for the keyword search tool. */
const SEARCH_DEFAULT_LIMIT = 10;
const SEARCH_MAX_LIMIT = 25;
/** Upper bound on docs the keyword search scans (recency-ordered). */
const SEARCH_SCAN_LIMIT = 300;

function tasksCol(repoId: string) {
  return db.collection(`apps/gitsync/repos/${repoId}/tasks`);
}

function toSummary(id: string, d: Record<string, unknown>): ExistingTaskSummary {
  return {
    taskId: id,
    title: (d.title as string | undefined) ?? '(untitled)',
    status: (d.status as string | undefined) ?? 'todo',
  };
}

function toWithDeps(id: string, d: Record<string, unknown>): ExistingTaskWithDeps {
  return {
    ...toSummary(id, d),
    dependsOn: Array.isArray(d.dependsOn) ? (d.dependsOn as string[]) : [],
  };
}

/** Lowercase word tokens of length >= 2 (mirrors dailyIntel.tokenize). */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length >= 2);
}

/**
 * One page of the repo's existing tasks ordered by document id, optionally
 * filtered to a single `status`. Pagination is keyed on the doc id via a cursor
 * so the model can scroll without ever receiving the full list. Best-effort →
 * empty page on any read failure.
 */
export async function listExistingTaskTitles(
  repoId: string,
  opts: { status?: string; cursor?: string } = {},
): Promise<ExistingTaskPage> {
  try {
    let q = tasksCol(repoId).orderBy('__name__').limit(TITLES_PAGE_SIZE + 1);
    if (opts.status) {
      // Filter in code (status is low-cardinality) to avoid a composite index
      // (database-guidelines Rule G). Over-fetch a page then trim.
      q = tasksCol(repoId).orderBy('__name__').limit(SEARCH_SCAN_LIMIT);
    }
    if (opts.cursor) q = q.startAfter(opts.cursor);

    const snap = await q.get();
    let rows = snap.docs.map((doc) => toSummary(doc.id, doc.data() ?? {}));
    if (opts.status) rows = rows.filter((r) => r.status === opts.status);

    const hasMore = rows.length > TITLES_PAGE_SIZE;
    const tasks = rows.slice(0, TITLES_PAGE_SIZE);
    const nextCursor = hasMore ? tasks[tasks.length - 1].taskId : null;
    return { tasks, nextCursor };
  } catch (err) {
    logger.warn('listExistingTaskTitles failed; returning empty page', {
      repoId,
      err: String(err),
    });
    return { tasks: [], nextCursor: null };
  }
}

/**
 * Keyword search over existing task titles (MVP — no embedding, prd D3/tool
 * note). Scans the most-recent {@link SEARCH_SCAN_LIMIT} tasks, scores by how
 * many query terms appear in the title, and returns the top `limit` matches with
 * their stored `dependsOn` (so the model can attach to the existing DAG).
 * Best-effort → [].
 */
export async function searchExistingTasks(
  repoId: string,
  query: string,
  limit = SEARCH_DEFAULT_LIMIT,
): Promise<ExistingTaskWithDeps[]> {
  const cap = Math.max(1, Math.min(limit, SEARCH_MAX_LIMIT));
  try {
    const snap = await tasksCol(repoId)
      .orderBy('__name__')
      .limit(SEARCH_SCAN_LIMIT)
      .get();
    const tasks = snap.docs.map((doc) => toWithDeps(doc.id, doc.data() ?? {}));

    const terms = new Set(tokenize(query));
    if (terms.size === 0) return tasks.slice(0, cap);

    const scored = tasks
      .map((t) => {
        const hay = t.title.toLowerCase();
        let score = 0;
        for (const term of terms) if (hay.includes(term)) score++;
        return { t, score };
      })
      .filter((s) => s.score > 0)
      .sort((a, b) => b.score - a.score);

    return scored.map((s) => s.t).slice(0, cap);
  } catch (err) {
    logger.warn('searchExistingTasks failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

/**
 * All existing tasks as id → stored `dependsOn`, used to build the combined
 * existing+new dependency graph for cycle detection. Reads the whole `tasks`
 * collection (repo-scoped) — the graph check needs every node. Throws on read
 * failure (the caller must NOT silently write on a broken graph read).
 */
export async function readExistingTaskGraph(
  repoId: string,
): Promise<Map<string, string[]>> {
  const snap = await tasksCol(repoId).get();
  const graph = new Map<string, string[]>();
  for (const doc of snap.docs) {
    const d = doc.data() ?? {};
    graph.set(doc.id, Array.isArray(d.dependsOn) ? (d.dependsOn as string[]) : []);
  }
  return graph;
}
