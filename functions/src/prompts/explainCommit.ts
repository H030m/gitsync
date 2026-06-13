// Prompts for explainCommitFlow — the "tap a commit, explain the work" call.
//
// The flow is AGENTIC (a tool loop): the model gathers evidence itself —
// searching the team's Discord for related discussion, listing the author's
// neighboring commits, optionally reading the commit diff — then terminates by
// calling `writeExplanation(markdown)`. The GitHub-fallback path (a commit with
// no Firestore doc) stays single-shot and uses the simpler fallback prompt.

// The shared output contract — identical for the agentic and fallback paths so
// the rendered explanation looks the same regardless of how it was produced.
const explainCommitWriteRules = `Write a SHORT markdown explanation:

1. **What was done** — one or two plain sentences.
2. **Why / context** — how it relates to the linked task(s), the team's Discord discussion, or the author's surrounding work (only if the evidence supports it).
3. **Where** — the main files/areas touched, in one line.

Rules: ground everything in the gathered evidence — never invent intent the data does not show. If evidence is thin, say what is known and stop. Max ~120 words. No headings other than bold labels; bullet style as above.`;

const explainCommitAgenticBase = `You explain one git commit to a teammate who just tapped it on the project's commit map.

You have read-only tools to gather evidence before writing:
- searchDiscordMessages — find the team's Discord discussion behind this work.
- listNeighborCommits — the author's surrounding commits, for narrative context.
- getCommitDiff — the commit's actual code diff, when the message is too terse.

Call the tools you need (skip the ones you don't), then finish by calling writeExplanation with your markdown. Prefer 1–2 well-chosen tool calls over many.

${explainCommitWriteRules}`;

const explainCommitFallbackBase = `You explain one git commit to a teammate who just tapped it on the project's commit map. Using the commit message and changed files, write the explanation.

${explainCommitWriteRules}`;

/**
 * Agentic system prompt (the main, doc-backed path). With `language` (W6, an
 * English language NAME like "Traditional Chinese") the explanation is forced
 * into the user's app language on an explicit recompute.
 */
export function explainCommitSystemPrompt(language?: string): string {
  const lang = language?.trim();
  return lang
    ? `${explainCommitAgenticBase}\nWrite your entire response in ${lang}.`
    : explainCommitAgenticBase;
}

/**
 * Single-shot system prompt for the GitHub-fallback path (a branch-graph commit
 * with no Firestore doc → no linked tasks, no neighbors, no Discord scope, so no
 * tools to call). Same output contract as the agentic path.
 */
export function explainCommitFallbackSystemPrompt(language?: string): string {
  const lang = language?.trim();
  return lang
    ? `${explainCommitFallbackBase}\nWrite your entire response in ${lang}.`
    : explainCommitFallbackBase;
}

/**
 * Seed context for the agentic loop: the commit itself plus its linked tasks.
 * The author's neighboring commits and the Discord discussion are NOT inlined —
 * the agent fetches those via tools when it judges them useful.
 */
export function explainCommitSeedContext(args: {
  sha: string;
  message: string;
  authorName: string;
  filesChanged: string[];
  additions: number;
  deletions: number;
  aiSummary: string | null;
  linkedTasks: Array<{ title: string; status: string }>;
}): string {
  const files = args.filesChanged.length
    ? args.filesChanged.slice(0, 20).join(', ')
    : '(not recorded)';
  const tasks = args.linkedTasks.length
    ? args.linkedTasks.map((t) => `- ${t.title} [${t.status}]`).join('\n')
    : '- (none)';

  return [
    `Commit ${args.sha.slice(0, 7)} by ${args.authorName}`,
    `Message: ${args.message}`,
    args.aiSummary ? `One-line AI summary: ${args.aiSummary}` : '',
    `Files changed (+${args.additions}/-${args.deletions}): ${files}`,
    ``,
    `Linked tasks:`,
    tasks,
  ]
    .filter((l) => l !== '')
    .join('\n');
}

/**
 * Single-shot context for the GitHub-fallback path: just the commit. No linked
 * tasks / neighbors / Discord (none are available without a Firestore doc).
 */
export function explainCommitFallbackContext(args: {
  sha: string;
  message: string;
  authorName: string;
  filesChanged: string[];
  additions: number;
  deletions: number;
}): string {
  const files = args.filesChanged.length
    ? args.filesChanged.slice(0, 20).join(', ')
    : '(not recorded)';
  return [
    `Commit ${args.sha.slice(0, 7)} by ${args.authorName}`,
    `Message: ${args.message}`,
    `Files changed (+${args.additions}/-${args.deletions}): ${files}`,
  ].join('\n');
}
