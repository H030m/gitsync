// assignTaskFlow — agentic OpenAI function-calling loop that picks the best
// assignee for a task. See ARCHITECTURE.md §5.2.

export interface AssignTaskInput {
  repoId: string;
  taskId: string;
}

export interface AssignTaskResult {
  assigneeId: string;
  reasoning: string;
}

export async function assignTaskFlow(
  _input: AssignTaskInput,
): Promise<AssignTaskResult> {
  // TODO: implement Sprint 3.
  //  - Register 4 tools: readTeamState, searchMemberCommits,
  //    getTaskDependents, finalizeAssignment
  //  - Loop max 5 rounds; exit when finalizeAssignment is called
  //  - `readTeamState` must return the 3-way identity map
  //    (userId / githubLogin / discordUserId) — see MEMORY.md 2026-05-26
  //    "users must add discordUserId column"
  throw new Error('assignTaskFlow not implemented yet');
}
