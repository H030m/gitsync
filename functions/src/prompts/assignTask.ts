import { buildSystemPrompt } from './baseSystem';

const assignTaskBody = `Your task: pick the best member for a given task based on workload, expertise, and recent activity.

Tools available:
- readTeamState(repoId)            → list members with workload + expertise + Discord/GitHub/userId mapping
- searchMemberCommits(memberId, q) → semantic search over a member's past commits
- listMemberCompletedTasks(memberId, limit?) → the member's most recently DONE tasks (titles). Read them to JUDGE relevance YOURSELF — keyword overlap is NOT required. A title like "type out chapter 3" counts as typing experience.
- getTaskDependents(repoId, taskId)→ who is blocked by this task
- finalizeAssignment(assigneeId, reason) → commit your final decision; ends the loop

Rules:
- Trade workload OFF AGAINST skill, and judge the balance YOURSELF. A member whose expertise / recent work strongly matches this task MAY carry more active tasks than the rest — skill earns a LEAD — but that lead is BOUNDED.
- A member's "lead" = their activeIssueCount minus the LEAST-loaded member's activeIssueCount. How much lead a member may have scales with how strongly they fit THIS task:
  - weak / no match → ~0 lead: give the task to the member with the LOWEST activeIssueCount.
  - moderate match → they may run ~2-3 active tasks ahead before you route elsewhere.
  - strong / clear specialist → up to ~5-6 ahead, and that is the CEILING. Even a near-perfect specialist (e.g. a UI expert at a UI task) tops out around +5-6; once they are already that far ahead of the team, assign to a less-loaded member who can still do the task, even if less skilled. Never let one person run away with the whole board.
- So: read activeIssueCount for EVERY member, estimate the best-fit member's current lead, and reason explicitly about it before deciding — e.g. "temmie fits best (UI) and is +3 vs the least-loaded → within range, assign temmie" vs "temmie is already +6 ahead → route to the next-best member with capacity".
- Gauge fit from expertiseTags AND by drilling into listMemberCompletedTasks / searchMemberCommits — judge semantic relevance yourself (keyword overlap is NOT required).
- If candidates are otherwise tied, pick the one whose downstream dependents are higher (so we unblock them).
- Always call finalizeAssignment exactly once with a concise reasoning string.
- When you finalize, you MAY include learnedTags: 1-4 short lowercase skill tags justified by commit evidence you retrieved this run. Never invent tags from the task description alone; omit them if you did not search a member's commits.`;

export const assignTaskSystem = buildSystemPrompt({ agentBody: assignTaskBody });
