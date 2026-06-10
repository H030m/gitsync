// Prompt for generateHandoffFlow. The flow pre-gathers all context (the
// receiving task, its completed prerequisites, related commits, Discord
// discussion, and the team roster) and injects it here as one user message —
// there is no agentic tool loop (mirrors explainCommit / discordDailyDigest),
// which keeps it cheap, deterministic, and safe to run best-effort on the
// task-completion trigger.

export const generateHandoffSystem = `You are a senior engineer writing a concise handoff document so the next engineer can pick up a task whose prerequisites just finished.

You are given: the task to pick up (with its acceptance criteria), the finished prerequisite tasks, the real commits and Discord discussion behind that work, and a roster mapping IDs to people's names.

Write GitHub-flavored markdown with exactly these sections:
- "What was done" — 2-4 bullets summarizing what the finished prerequisites delivered (cite commit subjects where useful).
- "Why we did it this way" — design decisions worth knowing, drawn from the commits/discussion (skip if there's no signal).
- "What's left for you" — concrete action items tied to THIS task's acceptance criteria.
- "Gotchas" — anything subtle (race conditions, missing tests, hardcoded values, follow-ups raised in chat).

Rules:
- Refer to people by their real name (use the roster; fall back to githubLogin).
- Ground every claim in the provided context — do NOT invent commits, files, or decisions. If a section has no signal, say so briefly rather than guessing.
- Be terse and skimmable. No preamble, no closing pleasantries — output only the markdown.`;

export interface HandoffContextInput {
  task: { title: string; description: string; acceptanceCriteria: string[] };
  prerequisites: Array<{ title: string; description: string; status: string }>;
  commits: Array<{
    sha: string;
    subject: string;
    aiSummary: string | null;
    author: string;
    filesChanged: number;
  }>;
  discord: Array<{ author: string; content: string }>;
  roster: Array<{ name: string | null; githubLogin: string | null }>;
}

export function generateHandoffContext(input: HandoffContextInput): string {
  const { task, prerequisites, commits, discord, roster } = input;

  const criteria = task.acceptanceCriteria.length
    ? task.acceptanceCriteria.map((c) => `  - ${c}`).join('\n')
    : '  (none specified)';

  const prereqs = prerequisites.length
    ? prerequisites
        .map(
          (p) =>
            `  - [${p.status}] ${p.title}${p.description ? ` — ${p.description}` : ''}`,
        )
        .join('\n')
    : '  (none)';

  const commitLines = commits.length
    ? commits
        .map(
          (c) =>
            `  - ${c.sha} (${c.author}, ${c.filesChanged} files): ${c.subject}` +
            (c.aiSummary ? `\n    summary: ${c.aiSummary}` : ''),
        )
        .join('\n')
    : '  (no related commits found)';

  const chat = discord.length
    ? discord.map((m) => `  - ${m.author}: ${m.content}`).join('\n')
    : '  (no related discussion found)';

  const people = roster.length
    ? roster
        .map((r) => `  - ${r.name ?? '?'}${r.githubLogin ? ` (@${r.githubLogin})` : ''}`)
        .join('\n')
    : '  (roster unavailable)';

  return [
    `TASK TO PICK UP:\n  ${task.title}${task.description ? `\n  ${task.description}` : ''}`,
    `ACCEPTANCE CRITERIA:\n${criteria}`,
    `FINISHED PREREQUISITES:\n${prereqs}`,
    `RELATED COMMITS:\n${commitLines}`,
    `RELATED DISCORD DISCUSSION:\n${chat}`,
    `TEAM ROSTER:\n${people}`,
  ].join('\n\n');
}
