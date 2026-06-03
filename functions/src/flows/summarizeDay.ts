// summarizeDayFlow — produces an agentic daily report for one repo + day from
// commits + completed tasks + Discord discussion. See ARCHITECTURE.md §5.4.
// Invoked by Cloud Tasks (fan-out from `scheduledDailyReport`) and by the
// `summarizeDay` callable (the Summary tab's Regenerate button).
//
// AGENTIC (upgrades the doc's "非 Agentic 單次" note): an OpenAI function-calling
// loop. The day's commits / tasks / roster are pre-fetched deterministically
// (so the per-member counts are exact — counting is never delegated to the LLM,
// AGENTIC_CONCEPTS §4 "pruning"); the agent then freely drills deeper via tools
// (`getDayDigest`, `searchPastCommits`) before calling `finalizeReport` with the
// narrative (summary / highlights / blockers / commit themes). Mirrors the
// `discordChatFlow` / `assignTaskFlow` loop pattern.
import { logger } from 'firebase-functions/v2';
import { FieldValue } from 'firebase-admin/firestore';
import type OpenAI from 'openai';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import { summarizeDaySystem, summarizeDayContext } from '../prompts/summarizeDay';
import {
  listDayCommits,
  listCompletedTasks,
  getDayDigest,
  searchPastCommits,
  computeContributions,
  readRoster,
  type MemberContributions,
} from '../tools/dailyIntel';
import type { CommitTheme, DailyReportNarrative } from '../types';

export interface SummarizeDayInput {
  repoId: string;
  date: string; // YYYY-MM-DD
}

export interface SummarizeDayResult {
  summary: string;
  highlights: string[];
  blockers: string[];
  commitThemes: CommitTheme[];
  memberContributions: MemberContributions;
  completedTaskIds: string[];
  commitCount: number;
}

const MAX_ROUNDS = 4;

const TOOLS: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'getDayDigest',
      description:
        "Get the AI digest (markdown) of the day's Discord discussion, to mine " +
        'for blockers, decisions, and context the commits alone do not show. ' +
        'Returns null when there is no digest for that day.',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchPastCommits',
      description:
        'Keyword search the repo history (across days) to ground a theme — e.g. ' +
        'find when a feature was last touched. Use sparingly; the day context is ' +
        'already provided.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search terms.' },
          limit: { type: 'number', description: 'Max commits (default 6).' },
        },
        required: ['query'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'finalizeReport',
      description:
        'Submit the finished daily report. Call this exactly once, after you ' +
        'have read the context, to end the task.',
      parameters: {
        type: 'object',
        properties: {
          summary: {
            type: 'string',
            description: '2-3 plain-English sentences for a non-technical reader.',
          },
          highlights: {
            type: 'array',
            items: { type: 'string' },
            description: "Today's key achievements, most important first.",
          },
          blockers: {
            type: 'array',
            items: { type: 'string' },
            description: 'Blockers/risks; empty array if none.',
          },
          commitThemes: {
            type: 'array',
            description: "The day's commits grouped into themes.",
            items: {
              type: 'object',
              properties: {
                theme: { type: 'string' },
                summary: { type: 'string' },
                commitCount: { type: 'number' },
              },
              required: ['theme', 'summary', 'commitCount'],
              additionalProperties: false,
            },
          },
        },
        required: ['summary', 'highlights', 'blockers', 'commitThemes'],
        additionalProperties: false,
      },
    },
  },
];

export async function summarizeDayFlow(
  input: SummarizeDayInput,
): Promise<SummarizeDayResult> {
  const { repoId, date } = input;
  logger.info('summarizeDayFlow: start', { repoId, date });

  // ---- Step 1: deterministic context (exact counts, not LLM-guessed) -------
  const [commits, tasks, roster] = await Promise.all([
    listDayCommits(repoId, date),
    listCompletedTasks(repoId, date),
    readRoster(repoId),
  ]);
  const memberContributions = computeContributions(commits, tasks, roster);
  const completedTaskIds = tasks.map((t) => t.id);

  // ---- Step 2: agentic narrative loop --------------------------------------
  const narrative = await runReportAgent(repoId, date, commits, tasks);

  // commitThemes counts come from the model's grouping; clamp to >= 0.
  const commitThemes = narrative.commitThemes.map((t) => ({
    ...t,
    commitCount: Math.max(0, Math.round(t.commitCount)),
  }));

  const result: SummarizeDayResult = {
    summary: narrative.summary,
    highlights: narrative.highlights,
    blockers: narrative.blockers,
    commitThemes,
    memberContributions,
    completedTaskIds,
    commitCount: commits.length,
  };

  // ---- Step 3: persist (Cloud Functions are the only writer; clients RO) ----
  await db.doc(`apps/gitsync/repos/${repoId}/dailyReports/${date}`).set({
    date,
    repoId,
    summary: result.summary,
    highlights: result.highlights,
    blockers: result.blockers,
    commitThemes: result.commitThemes,
    memberContributions: result.memberContributions,
    completedTasks: result.completedTaskIds,
    commitCount: result.commitCount,
    generatedAt: FieldValue.serverTimestamp(),
  });

  logger.info('summarizeDayFlow: wrote report', {
    repoId,
    date,
    commits: commits.length,
    tasks: tasks.length,
  });
  return result;
}

/** The OpenAI function-calling loop that authors the report narrative. */
async function runReportAgent(
  repoId: string,
  date: string,
  commits: Awaited<ReturnType<typeof listDayCommits>>,
  tasks: Awaited<ReturnType<typeof listCompletedTasks>>,
): Promise<DailyReportNarrative> {
  const openai = getOpenAI();
  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: 'system', content: summarizeDaySystem },
    { role: 'user', content: summarizeDayContext({ date, commits, tasks }) },
  ];

  for (let round = 0; round < MAX_ROUNDS; round++) {
    const forceFinalize = round === MAX_ROUNDS - 1;
    const completion = await openai.chat.completions.create({
      model: MODELS.fast,
      messages,
      tools: TOOLS,
      // On the last round, force the agent to finalize so we always get output.
      tool_choice: forceFinalize
        ? { type: 'function', function: { name: 'finalizeReport' } }
        : 'auto',
    });

    const choice = completion.choices[0]?.message;
    if (!choice) break;
    messages.push(choice);

    const toolCalls = choice.tool_calls ?? [];
    if (toolCalls.length === 0) continue; // model mused without a tool; loop.

    let finalized: DailyReportNarrative | null = null;
    const results = await Promise.all(
      toolCalls.map(async (call) => {
        if (call.type !== 'function') {
          return { id: call.id, content: 'unsupported tool call' };
        }
        const args = safeParse(call.function.arguments);
        switch (call.function.name) {
          case 'getDayDigest': {
            const digest = await getDayDigest(repoId, date);
            return {
              id: call.id,
              content: JSON.stringify(digest ?? { markdown: null }),
            };
          }
          case 'searchPastCommits': {
            const hits = await searchPastCommits(
              repoId,
              String(args.query ?? ''),
              typeof args.limit === 'number' ? args.limit : 6,
            );
            return { id: call.id, content: JSON.stringify(hits) };
          }
          case 'finalizeReport': {
            finalized = normalizeNarrative(args);
            return { id: call.id, content: 'ok' };
          }
          default:
            return { id: call.id, content: `unknown tool ${call.function.name}` };
        }
      }),
    );

    for (const r of results) {
      messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
    }
    if (finalized) return finalized;
  }

  // Loop exhausted without a finalize (should not happen — last round forces
  // it). Degrade to a deterministic summary so the report is never empty.
  logger.warn('summarizeDayFlow: agent did not finalize; using fallback', {
    repoId,
    date,
  });
  return fallbackNarrative(commits, tasks);
}

/** Coerce finalize-tool args into a well-formed narrative. */
function normalizeNarrative(args: Record<string, unknown>): DailyReportNarrative {
  const asStrings = (v: unknown): string[] =>
    Array.isArray(v) ? v.map((x) => String(x)).filter(Boolean) : [];
  const themes = Array.isArray(args.commitThemes) ? args.commitThemes : [];
  return {
    summary: String(args.summary ?? '').trim(),
    highlights: asStrings(args.highlights),
    blockers: asStrings(args.blockers),
    commitThemes: themes.map((t) => {
      const o = (t ?? {}) as Record<string, unknown>;
      return {
        theme: String(o.theme ?? '').trim(),
        summary: String(o.summary ?? '').trim(),
        commitCount: Number(o.commitCount ?? 0) || 0,
      };
    }),
  };
}

/** Deterministic narrative used only if the agent never finalizes. */
function fallbackNarrative(
  commits: Awaited<ReturnType<typeof listDayCommits>>,
  tasks: Awaited<ReturnType<typeof listCompletedTasks>>,
): DailyReportNarrative {
  const summary =
    commits.length === 0 && tasks.length === 0
      ? 'No commits or completed tasks were recorded for this day.'
      : `${commits.length} commit(s) landed and ${tasks.length} task(s) were ` +
        'completed.';
  return {
    summary,
    highlights: tasks.map((t) => `Completed: ${t.title}`),
    blockers: [],
    commitThemes: commits.length
      ? [
          {
            theme: 'Commits',
            summary: `${commits.length} commit(s) across the repo.`,
            commitCount: commits.length,
          },
        ]
      : [],
  };
}

function safeParse(raw: string | undefined): Record<string, unknown> {
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return {};
  }
}
