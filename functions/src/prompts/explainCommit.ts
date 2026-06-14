// Prompts for explainCommitFlow — the "tap a commit, explain the work" call.
//
// The flow is AGENTIC (a tool loop): the model gathers evidence itself —
// searching the team's Discord for related discussion, listing the author's
// neighboring commits, optionally reading the commit diff — then terminates by
// calling `writeExplanation(markdown)`. The GitHub-fallback path (a commit with
// no Firestore doc) stays single-shot and uses the simpler fallback prompt.

// Shared opening of the output contract (What / Why). The CHANGES section
// differs by path: the agentic path reads the real diff and gives a per-file
// before→after breakdown; the diff-less fallback can only name files.
const explainCommitWhatWhy = `1. **What was done** — one or two plain sentences.
2. **Why / context** — how it relates to the linked task(s), the team's Discord discussion, or the author's surrounding work (only if the evidence supports it).`;

// Agentic path: it HAS getCommitDiff, so demand a real change breakdown — the
// whole point of tapping a commit is to see what actually changed and how.
const explainCommitAgenticWriteRules = `Write a skimmable markdown explanation:

${explainCommitWhatWhy}
3. **Changes** — call getCommitDiff and read the patch, then list the files that meaningfully changed, ONE bullet per file, each as: \`path — what changed, from <old> to <new>\`. Be concrete and trace-like about the before→after (e.g. "exact-match author filter → fuzzy substring match", "added a guard before markIdempotent", "renamed field X to Y", "new section in the prompt"), NOT vague ("updated X", "improved Y", "adjusted logic"). Collapse generated / trivial files into a single closing bullet. If it is a MERGE commit (empty diff), say so in one line and instead summarize the work the merged branch brought in (use listNeighborCommits), one bullet per theme.

Rules: ground every bullet in the actual patch — never invent a change the diff does not show. If a file's change is unclear from the patch, say what it is at most. No hard length limit, but stay tight: one bullet per file, no filler, no closing pleasantry. Bold labels only.`;

// Fallback path: no diff tool — it only has the commit message + file names, so
// it cannot give before→after; keep the short "Where" line.
const explainCommitFallbackWriteRules = `Write a SHORT markdown explanation:

${explainCommitWhatWhy}
3. **Where** — the main files/areas touched, in one line, with what each likely does (inferred from the message).

Rules: ground everything in the commit message + file list — never invent intent the data does not show. If evidence is thin, say what is known and stop. Max ~120 words. Bold labels only.`;

const explainCommitAgenticBase = `You explain one git commit to a teammate who just tapped it on the project's commit map. They want to know WHAT actually changed and HOW — like a quick code trace, not a vague headline.

You have read-only tools to gather evidence before writing:
- getCommitDiff — the commit's actual code diff. Call this for any commit whose changes you must describe (i.e. almost always) — the Changes section depends on it.
- searchDiscordMessages — find the team's Discord discussion behind this work.
- listNeighborCommits — the author's surrounding commits (and, for a merge, the work it brought in).

Call the tools you need (getCommitDiff first for the Changes section), then finish by calling writeExplanation with your markdown.

${explainCommitAgenticWriteRules}`;

const explainCommitFallbackBase = `You explain one git commit to a teammate who just tapped it on the project's commit map. Using the commit message and changed files, write the explanation.

${explainCommitFallbackWriteRules}`;

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
