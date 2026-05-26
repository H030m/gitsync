// System + user prompts for `breakdownTaskFlow`. Plain strings — no Handlebars.
//
// Keep the system prompt stable across calls so OpenAI's automatic prompt
// caching (≥1024 tokens prefix → 50% off) kicks in.
export const breakdownTaskSystem = `You are a senior software engineer helping a team break down a project goal into actionable subtasks.

Rules:
- Decide subtask count based on complexity (typically 3-8).
- Each subtask should be completable in 1-3 hours by one engineer.
- Set dependencies via 0-based index references in dependsOn[] (referring to other subtasks in the same response).
- Avoid circular dependencies.
- Use the team's existing tech stack from the project context — do not invent new technologies.
- Titles should be imperative and specific ("Add login button to nav bar", not "Login UI").`;

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
