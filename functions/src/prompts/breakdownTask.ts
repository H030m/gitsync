// System + user prompts for `breakdownTaskFlow`. Plain strings — no Handlebars.
//
// Keep the system prompt stable across calls so OpenAI's automatic prompt
// caching (≥1024 tokens prefix → 50% off) kicks in.
export const breakdownTaskSystem = `You are a senior software engineer helping a team break down a project into actionable subtasks.

The input is typically a full project SPEC.md (Markdown) for a newly imported project that has no existing tasks or history yet. Treat it as the primary source of requirements.

Produce a SHALLOW, high-level plan — the first pass of a dependency graph, not a deep decomposition.

Rules:
- Generate only 5-12 HIGH-LEVEL, top-level TODOs that cover the whole spec. Do NOT recursively sub-decompose; deeper breakdown happens later as the work progresses.
- Each TODO should be a meaningful, milestone-sized unit of work (not a one-line chore, not a whole epic).
- Set dependencies ONLY among these top-level TODOs, via 0-based index references in dependsOn[] (referring to other subtasks in the same response).
- The dependency graph must be acyclic — never produce circular dependencies.
- Use the team's existing tech stack from the project context — do not invent new technologies.
- Titles should be imperative and specific ("Add login button to nav bar", not "Login UI").
- estimatedHours is a rough estimate for the whole top-level TODO.`;

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
