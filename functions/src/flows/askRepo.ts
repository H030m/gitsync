// askRepoFlow — GitSync's UNIFIED, repo-wide "ask anything" agent. One agentic
// OpenAI function-calling loop over the full read-only tool set (recent commits
// / completed tasks / Discord digests / past-commit + Discord semantic search /
// repo planning docs / task dependents / team roster) so a developer can ask a
// single input box about progress, people, code, and discussion — replacing the
// per-tab chats. See prd.md (06-12-w5-ask-repo).
//
// Skeleton cloned/extended from flows/dailyBriefChat.ts: MODELS.fast, a bounded
// round loop that runs every round's tool_calls in parallel and feeds the
// JSON-stringified results back, terminating when the model answers with no tool
// call (or a forced no-tools final answer at the round cap). Commits (deduped by
// sha) and Discord snippets (deduped by snippetKey) surfaced across the loop are
// returned alongside the answer as cited sources.
//
// Backend B — agent tool-trace: each round's executed tools are recorded to a
// best-effort Firestore side-channel (tools/agentTrace.ts) keyed by the
// client-generated runId, so the UI can stream the progress while waiting. Trace
// writes NEVER affect the flow (every helper swallows its own errors).
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import type OpenAI from 'openai';

import { getOpenAI, MODELS } from '../config';
import { askRepoSystem } from '../prompts/askRepo';
import { readProjectBrief, formatBriefForPrompt } from '../tools/projectBrief';
import {
  listRangeCommits,
  listRangeCompletedTasks,
  listRangeDigests,
  searchPastCommits,
  type DayCommit,
} from '../tools/dailyIntel';
import {
  searchDiscordMessages,
  type DiscordSnippet,
} from '../tools/discordSearch';
import { readRepoPlanningDocs } from '../tools/repoDocs';
import { getTaskDependents, readTeamState } from '../tools/assignTools';
import {
  startRun,
  appendStep,
  finishRun,
  TRACE_LABELS,
} from '../tools/agentTrace';

/** One prior conversation turn from the client. */
export interface AskRepoTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface AskRepoInput {
  repoId: string;
  question: string;
  history?: AskRepoTurn[];
  /** Client-generated id for the agent-trace doc. Absent → trace is a no-op. */
  runId?: string;
}

export interface AskRepoResult {
  answer: string;
  commits: DayCommit[]; // commits the agent surfaced (deduped by sha)
  snippets: DiscordSnippet[]; // Discord clusters surfaced (deduped by key)
}

const MAX_ROUNDS = 5;
const MAX_HISTORY_TURNS = 8;
/** Default look-back window (days) for the day-scoped tools (prd Q1). */
const DEFAULT_DAYS = 30;
/** Hard cap on the look-back window the model can request (prd Q1). */
const MAX_DAYS = 92;

/** Stable key for deduping a Discord snippet across tool calls (same rule as
 *  discordChat.ts: channelId : firstMessageId : lastMessageId). */
function snippetKey(s: DiscordSnippet): string {
  const first = s.messages[0]?.messageId ?? '';
  const last = s.messages[s.messages.length - 1]?.messageId ?? '';
  return `${s.channelId}:${first}:${last}`;
}

// The day-scoped tools accept an optional `days` window (prd Q1: default 30,
// hard cap 92); all-time lookups go through searchPastCommits / the Discord
// semantic search instead.
const DAYS_PARAM = {
  days: {
    type: 'number',
    description: `Look-back window in days (default ${DEFAULT_DAYS}, max ${MAX_DAYS}).`,
  },
} as const;

const TOOLS: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'listDayCommits',
      description:
        'List commits committed in the last `days` days (author, message, ' +
        'one-line AI summary, linked tasks). Start here for "what landed".',
      parameters: { type: 'object', properties: { ...DAYS_PARAM }, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'listCompletedTasks',
      description: 'List tasks that reached done in the last `days` days.',
      parameters: { type: 'object', properties: { ...DAYS_PARAM }, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'listRangeDigests',
      description:
        'Read the per-day AI digests of the last `days` days of Discord ' +
        'discussion (decisions, blockers). Returns [] when no day has a digest.',
      parameters: { type: 'object', properties: { ...DAYS_PARAM }, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchPastCommits',
      description:
        'Semantic search of the WHOLE commit history (all time) — for "when ' +
        'did we last…" / "who wrote…" / cross-period questions.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search terms.' },
          limit: { type: 'number', description: 'Max commits (default 8).' },
        },
        required: ['query'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchDiscordMessages',
      description:
        "Semantic search of the team's Discord messages. Returns grouped " +
        'conversation snippets (matched messages + surrounding context) — for ' +
        'exact wording / who-said-what / the back-and-forth around a topic.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Natural-language search terms.' },
        },
        required: ['query'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'readRepoPlanningDocs',
      description:
        "Read the repo's in-repo planning context (.trellis tasks/prd, " +
        'AGENTS.md/CLAUDE.md, docs) — project conventions and what is already ' +
        'done. Cheap (cached).',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'getTaskDependents',
      description:
        'List the tasks blocked by a given task (who is waiting on it).',
      parameters: {
        type: 'object',
        properties: {
          taskId: { type: 'string', description: 'The task id to check.' },
        },
        required: ['taskId'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'readTeamState',
      description:
        'List repo members (name + GitHub login) so you can refer to people ' +
        'by real name.',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
];

/** YYYY-MM-DD for `date` in Asia/Taipei (UTC+8), without a tz lib. */
function taipeiDateKey(date: Date): string {
  const taipei = new Date(date.getTime() + 8 * 60 * 60 * 1000);
  return taipei.toISOString().slice(0, 10);
}

/** Clamp the model-requested `days` into [1, MAX_DAYS], defaulting to 30. */
function clampDays(raw: unknown): number {
  const n = typeof raw === 'number' && Number.isFinite(raw) ? Math.floor(raw) : DEFAULT_DAYS;
  return Math.max(1, Math.min(n, MAX_DAYS));
}

export async function askRepoFlow(input: AskRepoInput): Promise<AskRepoResult> {
  const { repoId, question, runId } = input;
  const history = Array.isArray(input.history) ? input.history : [];

  const today = taipeiDateKey(new Date());
  const sinceKey = (days: number): string =>
    taipeiDateKey(new Date(Date.now() - (days - 1) * 24 * 60 * 60 * 1000));

  // Best-effort project-brief prefix (stable, cache-friendly; empty → '').
  const briefPrefix = formatBriefForPrompt(await readProjectBrief(repoId));

  const openai = getOpenAI();
  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: 'system', content: askRepoSystem(today, DEFAULT_DAYS) + briefPrefix },
    ...history
      .slice(-MAX_HISTORY_TURNS)
      .filter((t) => t && (t.role === 'user' || t.role === 'assistant') && t.content)
      .map((t) => ({ role: t.role, content: t.content })),
    { role: 'user', content: question },
  ];

  // Sources surfaced across rounds — commits deduped by sha, snippets by key,
  // both first-seen order (the order the agent found them).
  //
  // Commits the agent retrieves (both the listing tool and the semantic search)
  // are shown to the user as cards in a scrollable sources panel. A hard cap
  // keeps a broad "how's progress" question from surfacing the whole window; the
  // prompt tells the agent to summarize in prose and NOT paste commits as text.
  const MAX_SURFACED_COMMITS = 12;
  const surfacedCommits = new Map<string, DayCommit>();
  const collectCommits = (cs: DayCommit[]) => {
    for (const c of cs) {
      if (surfacedCommits.size >= MAX_SURFACED_COMMITS) break;
      if (!surfacedCommits.has(c.sha)) surfacedCommits.set(c.sha, c);
    }
  };
  const surfacedSnippets = new Map<string, DiscordSnippet>();
  const collectSnippets = (ss: DiscordSnippet[]) => {
    for (const s of ss) surfacedSnippets.set(snippetKey(s), s);
  };

  // Open the agent-trace run (no-op when no runId). Best-effort throughout.
  await startRun(repoId, runId, 'askRepo');

  try {
    for (let round = 0; round < MAX_ROUNDS; round++) {
      logger.info('askRepoFlow: round', { repoId, round });
      const completion = await openai.chat.completions.create({
        model: MODELS.fast,
        messages,
        tools: TOOLS,
        tool_choice: 'auto',
      });

      const choice = completion.choices[0]?.message;
      if (!choice) throw new HttpsError('internal', 'OpenAI returned no message');
      messages.push(choice);

      const toolCalls = choice.tool_calls ?? [];
      if (toolCalls.length === 0) {
        await finishRun(repoId, runId, 'done');
        return {
          answer: choice.content ?? '',
          commits: [...surfacedCommits.values()],
          snippets: [...surfacedSnippets.values()],
        };
      }

      const results = await Promise.all(
        toolCalls.map((call) => runTool(repoId, call, sinceKey, today, {
          collectCommits,
          collectSnippets,
        })),
      );
      for (const r of results) {
        messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
      }

      // One batch trace write per round — a step per tool the round executed.
      await appendStep(repoId, runId, results.map((r) => r.label));
    }

    // Out of rounds — force one final answer with no tools.
    logger.warn('askRepoFlow: round limit hit, forcing final answer', { repoId });
    await appendStep(repoId, runId, TRACE_LABELS.composing);
    const finalCompletion = await openai.chat.completions.create({
      model: MODELS.fast,
      messages: [
        ...messages,
        {
          role: 'user',
          content:
            'Now answer my question using what you found above. Do not call any more tools.',
        },
      ],
    });
    await finishRun(repoId, runId, 'done');
    return {
      answer: finalCompletion.choices[0]?.message?.content ?? '',
      commits: [...surfacedCommits.values()],
      snippets: [...surfacedSnippets.values()],
    };
  } catch (err) {
    // The flow failed (e.g. OpenAI down) — mark the run errored, then rethrow so
    // the handler still surfaces the failure to the client.
    await finishRun(repoId, runId, 'error');
    throw err;
  }
}

/** Execute one tool call, collect its sources, and return its trace label. */
async function runTool(
  repoId: string,
  call: OpenAI.Chat.Completions.ChatCompletionMessageToolCall,
  sinceKey: (days: number) => string,
  today: string,
  collect: {
    collectCommits: (cs: DayCommit[]) => void;
    collectSnippets: (ss: DiscordSnippet[]) => void;
  },
): Promise<{ id: string; content: string; label: string }> {
  if (call.type !== 'function') {
    return { id: call.id, content: 'unsupported tool call', label: '' };
  }
  const args = safeParse(call.function.arguments);
  const name = call.function.name;
  switch (name) {
    case 'listDayCommits': {
      const cs = await listRangeCommits(repoId, sinceKey(clampDays(args.days)), today);
      collect.collectCommits(cs); // surfaced to the panel (capped in collectCommits)
      return { id: call.id, content: JSON.stringify(cs), label: TRACE_LABELS.listDayCommits };
    }
    case 'listCompletedTasks': {
      const ts = await listRangeCompletedTasks(repoId, sinceKey(clampDays(args.days)), today);
      return { id: call.id, content: JSON.stringify(ts), label: TRACE_LABELS.listCompletedTasks };
    }
    case 'listRangeDigests': {
      const ds = await listRangeDigests(repoId, sinceKey(clampDays(args.days)), today);
      return { id: call.id, content: JSON.stringify(ds), label: TRACE_LABELS.listRangeDigests };
    }
    case 'searchPastCommits': {
      const cs = await searchPastCommits(
        repoId,
        String(args.query ?? ''),
        typeof args.limit === 'number' ? args.limit : 8,
      );
      collect.collectCommits(cs);
      return { id: call.id, content: JSON.stringify(cs), label: TRACE_LABELS.searchPastCommits };
    }
    case 'searchDiscordMessages': {
      const ss = await searchDiscordMessages(repoId, String(args.query ?? ''));
      collect.collectSnippets(ss);
      return { id: call.id, content: JSON.stringify(ss), label: TRACE_LABELS.searchDiscordMessages };
    }
    case 'readRepoPlanningDocs': {
      const docs = await readRepoPlanningDocs(repoId);
      return { id: call.id, content: JSON.stringify(docs.content), label: TRACE_LABELS.readRepoPlanningDocs };
    }
    case 'getTaskDependents': {
      // getTaskDependents/readTeamState can throw (unlike the dailyIntel tools);
      // degrade to an empty result so one failed signal never kills the answer.
      const ds = await getTaskDependents(repoId, String(args.taskId ?? '')).catch((err) => {
        logger.warn('askRepoFlow: getTaskDependents failed (best-effort)', { repoId, err: String(err) });
        return [];
      });
      return { id: call.id, content: JSON.stringify(ds), label: TRACE_LABELS.getTaskDependents };
    }
    case 'readTeamState': {
      const roster = await readTeamState(repoId)
        .then((rs) => rs.map((m) => ({ name: m.name, githubLogin: m.githubLogin })))
        .catch((err) => {
          logger.warn('askRepoFlow: readTeamState failed (best-effort)', { repoId, err: String(err) });
          return [];
        });
      return { id: call.id, content: JSON.stringify(roster), label: TRACE_LABELS.readTeamState };
    }
    default:
      return { id: call.id, content: `unknown tool ${name}`, label: '' };
  }
}

function safeParse(raw: string | undefined): Record<string, unknown> {
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return {};
  }
}
