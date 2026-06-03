import type { DayCommit, DayTask } from '../tools/dailyIntel';

export const summarizeDaySystem = `You are the daily intelligence reporter for one software repo. You turn a day's raw activity (commits, completed tasks, Discord discussion) into a short, useful report for the whole team — including non-technical stakeholders.

You have tools:
- getDayDigest(): read the AI digest of the day's Discord chat (for blockers/decisions).
- searchPastCommits(query): ground a theme in repo history when needed.
- finalizeReport(...): submit the finished report. Call it exactly once when done.

Workflow:
1. Read the day context you are given. If commits reference work that needs context, OR to find blockers, call getDayDigest first.
2. Group the commits into a few meaningful THEMES (e.g. "Auth", "Daily report UI"), each with a one-line plain summary and the number of commits it covers. This is the commit-message rollup developers rely on.
3. Then call finalizeReport with: a 2-3 sentence plain-English summary (lead with the most important achievement), highlights (key wins), blockers (from chat or stuck work — empty if none), and the commit themes.

Style: no marketing fluff; concrete; mention blockers honestly. Do NOT invent activity that is not in the context. Do NOT output per-member counts — the backend computes those.`;

/** Compact, cache-friendly day context. Heavy/raw detail is pruned to keep the
 *  prompt bounded (AGENTIC_CONCEPTS §4). */
export function summarizeDayContext(args: {
  date: string;
  commits: DayCommit[];
  tasks: DayTask[];
}): string {
  const { date, commits, tasks } = args;

  const commitLines = commits.length
    ? commits
        .map((c) => {
          const who = c.authorName || c.authorLogin || 'unknown';
          const line = c.aiSummary ? `${c.message} — ${c.aiSummary}` : c.message;
          return `- (${who}) ${line}`;
        })
        .join('\n')
    : '- (none)';

  const taskLines = tasks.length
    ? tasks.map((t) => `- ${t.title}`).join('\n')
    : '- (none)';

  return [
    `Date: ${date}`,
    ``,
    `Commits today (${commits.length}):`,
    commitLines,
    ``,
    `Tasks completed today (${tasks.length}):`,
    taskLines,
  ].join('\n');
}
