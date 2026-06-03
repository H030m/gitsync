// Reusable, read-only data-access tools for the daily intelligence hub
// (summary tab). They power BOTH the agentic `summarizeDayFlow` (daily report
// generation) and `dailyBriefChatFlow` ("ask AI about today").
//
// Design mirrors `tools/discordSearch.ts` and `tools/assignTools.ts`:
//   - thin functions: read Firestore, normalize, return plain JSON shapes;
//   - never call OpenAI, never mutate state;
//   - BEST-EFFORT — a Firestore read failure degrades to []/null + a
//     `logger.warn`, so one missing signal never kills the whole flow.
//
// Day boundaries are Asia/Taipei (UTC+8), reusing `taipeiDayBounds` so the
// daily report and the Discord digest agree on what "one day" means.
import { logger } from 'firebase-functions/v2';

import { db } from '../admin';
import { taipeiDayBounds } from '../flows/discordDailyDigest';
import { readTeamState, type TeamMemberState } from './assignTools';

// Re-export the digest readers so callers get every day-intel tool from one
// module (the chat agent reads the Discord digest for "what was discussed").
export {
  getDaySummary as getDayDigest,
  listDaySummaries as listDayDigests,
  type DaySummary as DayDigest,
} from './discordSearch';

// ---- listDayCommits --------------------------------------------------------

/** A commit as the day-intel tools (and the report agent) see it. */
export interface DayCommit {
  sha: string;
  message: string; // first line only (keeps the agent prompt bounded)
  authorLogin: string;
  authorName: string;
  aiSummary: string | null; // one-line summary from onCommitCreated
  linkedTaskIds: string[];
  additions: number;
  deletions: number;
}

const DAY_COMMIT_LIMIT = 200;

/**
 * Commits committed on the given Asia/Taipei calendar day, oldest first.
 * Returns [] on a malformed date or a read failure (best-effort).
 */
export async function listDayCommits(
  repoId: string,
  date: string,
): Promise<DayCommit[]> {
  try {
    const { start, end } = taipeiDayBounds(date);
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/commits`)
      .where('committedAt', '>=', start)
      .where('committedAt', '<', end)
      .orderBy('committedAt', 'asc')
      .limit(DAY_COMMIT_LIMIT)
      .get();
    return snap.docs.map((d) => toDayCommit(d.id, d.data() ?? {}));
  } catch (err) {
    logger.warn('listDayCommits failed; returning [] (best-effort)', {
      repoId,
      date,
      err: String(err),
    });
    return [];
  }
}

function toDayCommit(sha: string, data: Record<string, unknown>): DayCommit {
  const author = (data.author as Record<string, unknown> | undefined) ?? {};
  const message = ((data.message as string | undefined) ?? '').split('\n')[0];
  return {
    sha,
    message,
    authorLogin: (author.login as string | undefined) ?? '',
    authorName: (author.name as string | undefined) ?? '',
    aiSummary: (data.aiSummary as string | undefined) ?? null,
    linkedTaskIds: (data.linkedTaskIds as string[] | undefined) ?? [],
    additions: (data.additions as number | undefined) ?? 0,
    deletions: (data.deletions as number | undefined) ?? 0,
  };
}

// ---- listCompletedTasks ----------------------------------------------------

/** A task that reached `done` on the given day, as the agent sees it. */
export interface DayTask {
  id: string;
  title: string;
  assigneeId: string | null;
  description: string;
}

const DAY_TASK_LIMIT = 100;

/**
 * Tasks whose status is `done` and whose `updatedAt` lands on the given
 * Asia/Taipei day. (Tasks carry no dedicated `completedAt`; a done task's
 * last update is its completion — see models/task.dart.) Best-effort → [].
 */
export async function listCompletedTasks(
  repoId: string,
  date: string,
): Promise<DayTask[]> {
  try {
    const { start, end } = taipeiDayBounds(date);
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/tasks`)
      .where('status', '==', 'done')
      .where('updatedAt', '>=', start)
      .where('updatedAt', '<', end)
      .limit(DAY_TASK_LIMIT)
      .get();
    return snap.docs.map((d) => {
      const t = d.data() ?? {};
      return {
        id: d.id,
        title: (t.title as string | undefined) ?? '',
        assigneeId: (t.assigneeId as string | undefined) ?? null,
        description: (t.description as string | undefined) ?? '',
      };
    });
  } catch (err) {
    logger.warn('listCompletedTasks failed; returning [] (best-effort)', {
      repoId,
      date,
      err: String(err),
    });
    return [];
  }
}

// ---- searchPastCommits -----------------------------------------------------

const PAST_SCAN_LIMIT = 300;
const PAST_DEFAULT = 8;
const PAST_MAX = 20;

/** Lowercase word tokens of length >= 2. */
function tokenize(text: string): string[] {
  return text
    .toLowerCase()
    .split(/[^\p{L}\p{N}]+/u)
    .filter((t) => t.length >= 2);
}

/**
 * Keyword search over the repo's recent commit history (across days), so the
 * brief-chat agent can answer "when did we last touch X / who wrote Y". This
 * is a keyword + recency ranker over the latest {@link PAST_SCAN_LIMIT}
 * commits — it needs no vector index and runs unchanged against the fake
 * backend. Falls back to the most recent commits when nothing matches.
 * Best-effort → [].
 */
export async function searchPastCommits(
  repoId: string,
  query: string,
  limit = PAST_DEFAULT,
): Promise<DayCommit[]> {
  const cap = Math.max(1, Math.min(limit, PAST_MAX));
  try {
    const snap = await db
      .collection(`apps/gitsync/repos/${repoId}/commits`)
      .orderBy('committedAt', 'desc')
      .limit(PAST_SCAN_LIMIT)
      .get();
    const commits = snap.docs.map((d) => toDayCommit(d.id, d.data() ?? {}));

    const terms = new Set(tokenize(query));
    if (terms.size === 0) return commits.slice(0, cap);

    const scored = commits
      .map((c) => {
        const hay = `${c.message} ${c.aiSummary ?? ''}`.toLowerCase();
        let score = 0;
        for (const t of terms) if (hay.includes(t)) score++;
        return { c, score };
      })
      .filter((s) => s.score > 0)
      .sort((a, b) => b.score - a.score);

    return (scored.length ? scored.map((s) => s.c) : commits).slice(0, cap);
  } catch (err) {
    logger.warn('searchPastCommits failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}

// ---- computeContributions --------------------------------------------------

/** Per-member tallies for one day, keyed by userId. */
export type MemberContributions = Record<
  string,
  { tasksDone: number; commits: number }
>;

/**
 * Deterministically tally per-member contributions from the day's commits +
 * completed tasks. Counting is done in TS (never delegated to the LLM, which
 * cannot be trusted to count) keyed by `userId`:
 *   - commits are attributed via `author.login → userId` using the roster;
 *     commits whose author maps to no member are bucketed under their login so
 *     they are still surfaced.
 *   - tasksDone is counted per `assigneeId`.
 */
export function computeContributions(
  commits: DayCommit[],
  tasks: DayTask[],
  roster: TeamMemberState[],
): MemberContributions {
  const loginToUser = new Map<string, string>();
  for (const m of roster) {
    if (m.githubLogin) loginToUser.set(m.githubLogin.toLowerCase(), m.userId);
  }

  const out: MemberContributions = {};
  const bump = (key: string, field: 'tasksDone' | 'commits') => {
    if (!key) return;
    const cur = out[key] ?? { tasksDone: 0, commits: 0 };
    cur[field] += 1;
    out[key] = cur;
  };

  for (const c of commits) {
    const key = loginToUser.get(c.authorLogin.toLowerCase()) ?? c.authorLogin;
    bump(key, 'commits');
  }
  for (const t of tasks) {
    if (t.assigneeId) bump(t.assigneeId, 'tasksDone');
  }
  return out;
}

/** Thin wrapper so the flow can fetch the roster without importing assignTools. */
export async function readRoster(repoId: string): Promise<TeamMemberState[]> {
  try {
    return await readTeamState(repoId);
  } catch (err) {
    logger.warn('readRoster failed; returning [] (best-effort)', {
      repoId,
      err: String(err),
    });
    return [];
  }
}
