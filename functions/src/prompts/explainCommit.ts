// Prompts for explainCommitFlow — the "tap a commit, explain the work" call.

const explainCommitSystemBase = `You explain one git commit to a teammate who just tapped it on the project's commit map. Using the commit message, changed files, linked tasks, and the author's neighboring commits, write a SHORT markdown explanation:

1. **What was done** — one or two plain sentences.
2. **Why / context** — how it relates to the linked task(s) or the author's surrounding work (only if the context supports it).
3. **Where** — the main files/areas touched, in one line.

Rules: ground everything in the given context — never invent intent the data does not show. If context is thin, say what is known and stop. Max ~120 words. No headings other than bold labels; bullet style as above.`;

/**
 * Commit work-summary system prompt. With `language` (W6, an English language
 * NAME like "Traditional Chinese") the explanation is forced into the user's
 * app language on an explicit recompute; without it the prompt is
 * byte-identical to before (the cached single-language path).
 */
export function explainCommitSystemPrompt(language?: string): string {
  const lang = language?.trim();
  return lang
    ? `${explainCommitSystemBase}\nWrite your entire response in ${lang}.`
    : explainCommitSystemBase;
}

export function explainCommitContext(args: {
  sha: string;
  message: string;
  authorName: string;
  filesChanged: string[];
  additions: number;
  deletions: number;
  aiSummary: string | null;
  linkedTasks: Array<{ title: string; status: string }>;
  neighborCommits: Array<{ sha: string; message: string }>;
}): string {
  const files = args.filesChanged.length
    ? args.filesChanged.slice(0, 20).join(', ')
    : '(not recorded)';
  const tasks = args.linkedTasks.length
    ? args.linkedTasks.map((t) => `- ${t.title} [${t.status}]`).join('\n')
    : '- (none)';
  const neighbors = args.neighborCommits.length
    ? args.neighborCommits.map((n) => `- ${n.sha} ${n.message}`).join('\n')
    : '- (none)';

  return [
    `Commit ${args.sha.slice(0, 7)} by ${args.authorName}`,
    `Message: ${args.message}`,
    args.aiSummary ? `One-line AI summary: ${args.aiSummary}` : '',
    `Files changed (+${args.additions}/-${args.deletions}): ${files}`,
    ``,
    `Linked tasks:`,
    tasks,
    ``,
    `Author's neighboring commits (newest first):`,
    neighbors,
  ]
    .filter((l) => l !== '')
    .join('\n');
}
