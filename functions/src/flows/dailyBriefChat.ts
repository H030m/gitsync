// dailyBriefChatFlow — agentic "ask AI about today" chat for the Summary tab
// (the developer intelligence hub). The model answers a natural-language
// question about a given day's activity by calling read-only tools over the
// day's commits, completed tasks, and Discord digest — plus repo history for
// "when did we last…" questions. Mirrors discordChatFlow (function-calling loop
// until the model answers without a tool call).
//
// Every commit the tools surface across the loop is collected (deduped by sha)
// and returned alongside the answer so the client can show its sources.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import type OpenAI from 'openai';

import { getOpenAI, MODELS } from '../config';
import { dailyBriefSystem } from '../prompts/dailyBrief';
import {
  listRangeCommits,
  listRangeCompletedTasks,
  listRangeDigests,
  searchPastCommits,
  type DayCommit,
} from '../tools/dailyIntel';

/** One prior conversation turn from the client. */
export interface BriefChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

export interface DailyBriefInput {
  repoId: string;
  date: string; // start of the period the chat is scoped to (YYYY-MM-DD)
  endDate?: string; // inclusive end; defaults to `date` (single day)
  question: string;
  history?: BriefChatTurn[];
}

export interface DailyBriefResult {
  answer: string;
  commits: DayCommit[]; // commits the agent surfaced (deduped by sha)
}

const MAX_ROUNDS = 4;
const MAX_HISTORY_TURNS = 8;

const TOOLS: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'listDayCommits',
      description:
        'List every commit committed inside the scoped period (author, ' +
        'message, one-line AI summary, linked tasks). Start here for "what ' +
        'landed".',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'listCompletedTasks',
      description: 'List the tasks that reached done inside the scoped period.',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'listRangeDigests',
      description:
        "Read the per-day AI digests of the scoped period's Discord discussion " +
        '(decisions, blockers). Returns [] when no day has a digest.',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchPastCommits',
      description:
        'Keyword-search the repo history ACROSS days — for "when did we last…" / ' +
        '"who wrote…" questions that go beyond the scoped day.',
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
];

export async function dailyBriefChatFlow(
  input: DailyBriefInput,
): Promise<DailyBriefResult> {
  const { repoId, date, question } = input;
  const endDate = input.endDate ?? date;
  const history = Array.isArray(input.history) ? input.history : [];

  const openai = getOpenAI();
  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: 'system', content: dailyBriefSystem(date, endDate) },
    ...history
      .slice(-MAX_HISTORY_TURNS)
      .filter((t) => t && (t.role === 'user' || t.role === 'assistant') && t.content)
      .map((t) => ({ role: t.role, content: t.content })),
    { role: 'user', content: question },
  ];

  // Commits surfaced across rounds, deduped by sha, first-seen order.
  const surfaced = new Map<string, DayCommit>();
  const collect = (cs: DayCommit[]) => {
    for (const c of cs) if (!surfaced.has(c.sha)) surfaced.set(c.sha, c);
  };

  for (let round = 0; round < MAX_ROUNDS; round++) {
    logger.info('dailyBriefChatFlow: round', { repoId, date, round });
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
      return { answer: choice.content ?? '', commits: [...surfaced.values()] };
    }

    const results = await Promise.all(
      toolCalls.map(async (call) => {
        if (call.type !== 'function') {
          return { id: call.id, content: 'unsupported tool call' };
        }
        const args = safeParse(call.function.arguments);
        switch (call.function.name) {
          case 'listDayCommits': {
            const cs = await listRangeCommits(repoId, date, endDate);
            collect(cs);
            return { id: call.id, content: JSON.stringify(cs) };
          }
          case 'listCompletedTasks': {
            const ts = await listRangeCompletedTasks(repoId, date, endDate);
            return { id: call.id, content: JSON.stringify(ts) };
          }
          case 'listRangeDigests': {
            const ds = await listRangeDigests(repoId, date, endDate);
            return { id: call.id, content: JSON.stringify(ds) };
          }
          case 'searchPastCommits': {
            const cs = await searchPastCommits(
              repoId,
              String(args.query ?? ''),
              typeof args.limit === 'number' ? args.limit : 8,
            );
            collect(cs);
            return { id: call.id, content: JSON.stringify(cs) };
          }
          default:
            return { id: call.id, content: `unknown tool ${call.function.name}` };
        }
      }),
    );

    for (const r of results) {
      messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
    }
  }

  // Out of rounds — force one final answer with no tools.
  logger.warn('dailyBriefChatFlow: round limit hit, forcing final answer', {
    repoId,
    date,
  });
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
  return {
    answer: finalCompletion.choices[0]?.message?.content ?? '',
    commits: [...surfaced.values()],
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
