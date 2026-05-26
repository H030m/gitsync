// summarizeDayFlow — produces a daily summary from commits + completed tasks
// + Discord discussion. See ARCHITECTURE.md §5.4. Invoked by Cloud Tasks
// (fan-out from `scheduledDailyReport`), not directly by Flutter.

export interface SummarizeDayInput {
  repoId: string;
  date: string; // YYYY-MM-DD
}

export interface SummarizeDayResult {
  summary: string;
  memberContributions: Record<string, { tasksDone: number; commits: number }>;
}

export async function summarizeDayFlow(
  _input: SummarizeDayInput,
): Promise<SummarizeDayResult> {
  // TODO: implement Sprint 4.
  //  - Aggregate completed tasks + commits + Discord discussion
  //  - One OpenAI call with structured outputs (DailySummarySchema)
  //  - Write to `dailyReports/{date}`
  throw new Error('summarizeDayFlow not implemented yet');
}
