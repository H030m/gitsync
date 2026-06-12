// Zod schemas for AI inputs/outputs.
//
// IMPORTANT: For LLM-generated `dependsOn`, the schema uses `number[]`
// (0-based indices into the same response). The backend translates these to
// real `string[]` taskIds (Firestore doc IDs) before persisting. See
// MEMORY.md 2026-05-26 "dependsOn type contract".
import { z } from 'zod';

// ---- breakdownTaskFlow ------------------------------------------------------

export const SubtaskFromLLMSchema = z.object({
  title: z.string().describe('Short, imperative title'),
  description: z.string(),
  dependsOn: z
    .array(z.number().int())
    .describe('0-based indices of prerequisite subtasks in this same array'),
  estimatedHours: z.number(),
});

export const BreakdownOutputSchema = z.object({
  subtasks: z.array(SubtaskFromLLMSchema),
});

export type BreakdownOutput = z.infer<typeof BreakdownOutputSchema>;

// ---- assignTaskFlow ---------------------------------------------------------

export const AssignmentDecisionSchema = z.object({
  assigneeId: z.string(),
  reasoning: z.string(),
});

export type AssignmentDecision = z.infer<typeof AssignmentDecisionSchema>;

// ---- generateHandoffFlow ----------------------------------------------------

export const HandoffReviewSchema = z.object({
  score: z.number().int().min(1).max(5),
  gaps: z.array(z.string()),
});

export type HandoffReview = z.infer<typeof HandoffReviewSchema>;

// ---- summarizeDayFlow -------------------------------------------------------

export const DailySummarySchema = z.object({
  summary: z.string(),
  memberContributions: z.record(
    z.string(),
    z.object({ tasksDone: z.number().int(), commits: z.number().int() }),
  ),
});

export type DailySummary = z.infer<typeof DailySummarySchema>;

// The agentic daily report (Summary tab "intelligence hub"). The agent gathers
// the day's commits / completed tasks / Discord digest via tools, then calls
// `finalizeReport` with this shape. `memberContributions` is filled in
// deterministically by the backend (TS counts), NOT by the model — so the
// schema here is the LLM-authored narrative only.
export const CommitThemeSchema = z.object({
  theme: z.string().describe('Short label for a group of related commits'),
  summary: z.string().describe('One plain sentence on what changed'),
  commitCount: z.number().int().describe('How many commits fall under it'),
});

export type CommitTheme = z.infer<typeof CommitThemeSchema>;

export const DailyReportNarrativeSchema = z.object({
  summary: z
    .string()
    .describe('2-3 plain-English sentences for a non-technical stakeholder'),
  highlights: z
    .array(z.string())
    .describe("Today's key achievements, most important first"),
  blockers: z
    .array(z.string())
    .describe('Blockers/risks raised in chat or stuck tasks; [] if none'),
  commitThemes: z
    .array(CommitThemeSchema)
    .describe('The day’s commits grouped into themes (commit-message rollup)'),
});

export type DailyReportNarrative = z.infer<typeof DailyReportNarrativeSchema>;
