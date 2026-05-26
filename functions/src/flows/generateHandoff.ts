// generateHandoffFlow — agentic loop + self-review producing a handoff doc
// for a completed task. See ARCHITECTURE.md §5.3.

export interface GenerateHandoffInput {
  repoId: string;
  taskId: string;
}

export interface GenerateHandoffResult {
  handoffMarkdown: string;
}

export async function generateHandoffFlow(
  _input: GenerateHandoffInput,
): Promise<GenerateHandoffResult> {
  // TODO: implement Sprint 3.
  // Phase 1 — Draft loop (max 5 rounds): readTeamRoster, findDownstreamTask,
  //   listRelatedCommits, getCommitDiff, searchDiscordMessages,
  //   searchPastCommits, draftHandoff.
  // Phase 2 — Self review (1 round): GPT-4o-mini rates 1-5, lists gaps; if
  //   score < 4 and rounds < 5 → back to Phase 1, else finalizeHandoff.
  throw new Error('generateHandoffFlow not implemented yet');
}
