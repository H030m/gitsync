// System + user prompts for `breakdownTaskFlow`. Common rules (identity /
// grounding / language) come from the top-level base (prompts/baseSystem.ts);
// this holds the decomposition rules. The W6 `language` is routed through
// buildSystemPrompt.
import { buildSystemPrompt } from './baseSystem';

const breakdownTaskSystemBase = `Your task: help a team break a project into actionable subtasks.

The input is typically a full project SPEC.md (Markdown) for a newly imported project that has no existing tasks or history yet. Treat it as the primary source of requirements.

Produce a SHALLOW, high-level plan — the first pass of a dependency graph, not a deep decomposition.

Rules:
- Generate only 5-12 HIGH-LEVEL, top-level TODOs that cover the whole spec. Do NOT recursively sub-decompose; deeper breakdown happens later as the work progresses.
- Each TODO should be a meaningful, milestone-sized unit of work (not a one-line chore, not a whole epic).
- Set dependencies via 0-based index references in dependsOn[]. ONLY add a dependency when task B genuinely cannot start until task A finishes (e.g. B reads a database that A creates). Tasks that CAN run in parallel MUST have empty dependsOn — do NOT chain them sequentially just because you listed them in order. A wide, parallel graph is better than a narrow, serial chain.
- The dependency graph must be acyclic — never produce circular dependencies.
- Use the team's existing tech stack from the project context — do not invent new technologies.
- Titles should be imperative and specific ("Add login button to nav bar", not "Login UI").
- estimatedHours is a rough estimate for the whole top-level TODO.
- Write the task titles and descriptions in the SAME language as the spec/project context (e.g. if the spec is written in Chinese, the tasks must be in Chinese).`;

/**
 * Breakdown system prompt. With `language` (W6, a human-readable English
 * language NAME like "Traditional Chinese") the task titles/descriptions are
 * forced into the user's app language; without it the prompt is byte-identical
 * to the base (and the base rule still tells the model to follow the spec's
 * language). The directive is the same trailing line used across the other W6
 * flows (prompts/generateHandoff.ts).
 */
export function breakdownTaskSystem(language?: string): string {
  return buildSystemPrompt({ agentBody: breakdownTaskSystemBase, language });
}

export function breakdownTaskUser(input: {
  projectContext: string;
  goal: string;
}): string {
  return `Project context:
${input.projectContext}

Goal to break down:
${input.goal}

Return JSON matching the schema.`;
}

// ---- INCREMENTAL breakdown (agentic, repo already has tasks) ----------------
//
// Routed through buildSystemPrompt (GITSYNC_BASE_SYSTEM + this body) like every
// other agent. The body holds ONLY the incremental-specific rules; generic
// identity / grounding / language live in the shared base. No task data is
// interpolated, so the prompt stays cache-friendly and existing tasks are
// explored via TOOLS rather than dumped into the prompt (prd D5: context must
// not grow with task count).
const incrementalBreakdownSystemBase = `Your task: do an INCREMENTAL breakdown of a goal into actionable subtasks. This repository ALREADY has tasks — add ONLY what is genuinely missing, do not re-plan the project.

Workflow (always in this order):
1. EXPLORE what already exists before generating anything. Do NOT assume; do NOT dump the task list — discover it via the tools:
   - listExistingTaskTitles({status?, cursor?}) — page through the current tasks ({taskId,title,status}). Start here to learn the shape of the plan. Use the returned nextCursor to page; filter by status if useful.
   - searchExistingTasks({query, limit?}) — keyword-search existing tasks related to a topic; returns {taskId,title,status,dependsOn} so you can wire dependencies to them.
2. GROUND your plan in the project's actual state (not just the possibly-stale task list):
   - searchPastCommits({query, limit?}) — semantic search of real commit history, to spot work that is already done even if no task is marked complete.
   - readRepoPlanningDocs() — the repo's in-repo planning docs (.trellis tasks/prd, AGENTS.md/CLAUDE.md, docs).
3. GENERATE only the missing top-level TODOs, then call submitBreakdown.

Rules:
- Do NOT duplicate an existing task. If the goal is already covered (in tasks or already built per commits), add fewer subtasks — or none.
- Keep it SHALLOW: meaningful, milestone-sized top-level TODOs (not one-line chores, not whole epics). Do not recursively sub-decompose.
- A new subtask may depend on other NEW subtasks (dependsOnNew: 0-based indices into your submitted array) AND on EXISTING tasks (dependsOnExisting: real taskIds you saw via the tools). Use the real taskId string exactly as returned by the tools — never invent ids.
- ONLY add a dependency when the blocked task genuinely cannot start until the other finishes. Tasks that CAN run in parallel MUST have empty dependency arrays — do NOT chain them sequentially. A wide, parallel graph is better than a narrow, serial chain.
- The combined graph (existing tasks + your new ones) MUST be acyclic.
- Titles should be imperative and specific.
- You MUST finish by calling submitBreakdown exactly once. Returning prose without calling it does not count.`;

/**
 * Incremental breakdown system prompt. Routed through buildSystemPrompt so it
 * carries the shared GITSYNC_BASE_SYSTEM prefix. With `language` (W6, a
 * human-readable English language NAME like "Traditional Chinese") the output is
 * forced into that language; without it the prompt is byte-identical to the base
 * (cache-friendly). Same shape as breakdownTaskSystem / generateHandoff (W6).
 */
export function incrementalBreakdownSystem(language?: string): string {
  return buildSystemPrompt({ agentBody: incrementalBreakdownSystemBase, language });
}

/** Initial user message for the incremental loop — just the goal + a nudge to
 *  explore first. No task list is embedded (that is what the tools are for). */
export function incrementalBreakdownUser(goal: string): string {
  return `Goal to break down (incrementally — the repo already has tasks):
${goal}

First explore the existing tasks and the project's real state with the tools, then call submitBreakdown with only the missing subtasks.`;
}
