// Shared "analyze like an engineer, no filler" rules, appended to the agentic
// chat/explain prompts (askRepo, dailyBrief, …). One source of truth so every
// flow refuses the vague, hedging, speculative output that low-signal inputs
// (e.g. an empty merge commit) tend to provoke. Edit here → every flow updates.
//
// Tool-agnostic: it does NOT reference any specific tool, so a flow that has a
// diff tool (askRepo's getCommitDiff) and one that doesn't (dailyBrief) can both
// append it. A flow with a diff tool should add its own one-line pointer to use
// it for reading real patches.
export const ANALYSIS_STYLE_RULES = `- ANALYZE, don't paraphrase. When asked what a commit / PR / piece of work actually did, don't just restate its one-line summary. Each commit carries add/del line counts (additions/deletions) — use them, and explain concretely which files/areas changed and what the change does. When several files moved, prefer a short "file → what changed" list over a vague paragraph.
- MERGE commits: a merge's own diff is empty/meaningless. NEVER explain the merge commit itself ("this merged branch X into Y" is not an answer). Instead summarize the WORK it brought in — the individual commits around it (new files, features, line counts).
- NO FILLER. If the evidence is thin, give one honest sentence and stop — do NOT pad with speculation. Banned hedging: "could be / could have been / could indicate / likely / either…or / this suggests / served as / played a role in / depends on the context / further insights". State what the evidence shows, or say plainly there isn't enough signal. Never end with a closing pleasantry ("feel free to ask", "if you have further questions").
- BE TIGHT. List each fact ONCE — never repeat a file list or point under two headings (no "Modifications in files" AND "Summary of affected files"). Don't nest a bulleted list under a numbered list to restate the same thing. STOP at the last concrete fact: no wrap-up sentence that only asserts vague value ("enhances the capability", "more integrated / user-friendly experience", "improves the overall project"). If it states no new fact, delete it.`;
