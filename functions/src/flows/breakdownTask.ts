// breakdownTaskFlow — splits a goal into actionable subtasks.
//
// TWO PATHS, auto-detected by whether the repo already has tasks (prd D1):
//
//   - EMPTY repo  → the original SINGLE-SHOT structured-output breakdown
//     (`openai.beta.chat.completions.parse`). Unchanged, low-risk first pass.
//   - NON-EMPTY repo → an INCREMENTAL agentic function-calling loop (mirrors
//     flows/assignTask.ts): the model explores the EXISTING tasks + real project
//     state via repo-scoped tools (never dumping the whole task list — prd D5),
//     then submits ONLY the missing subtasks. New subtasks may depend on
//     existing taskIds, and the combined existing+new graph is cycle-checked.
//
// Both paths pre-generate Firestore taskIds before writing so the LLM's index /
// existing-id references translate into real taskIds in one batch. The flow does
// NOT touch `isBreakingDown` — the handler owns that lock (error-handling.md).
//
// Detailed contract: ARCHITECTURE.md §5.1 + MEMORY.md 2026-05-26
// "dependsOn type contract" + prd 06-15-incremental-breakdown-repo-memory.
import { logger } from 'firebase-functions/v2';
import { HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { zodResponseFormat } from 'openai/helpers/zod';
import type OpenAI from 'openai';

import { db } from '../admin';
import { getOpenAI, MODELS } from '../config';
import {
  breakdownTaskSystem,
  breakdownTaskUser,
  incrementalBreakdownSystem,
  incrementalBreakdownUser,
} from '../prompts/breakdownTask';
import { readRepoPlanningDocs } from '../tools/repoDocs';
import { readProjectBrief, formatBriefForPrompt } from '../tools/projectBrief';
import { searchPastCommits } from '../tools/dailyIntel';
import {
  listExistingTaskTitles,
  searchExistingTasks,
  readExistingTaskGraph,
} from '../tools/breakdownTools';
import {
  BreakdownOutputSchema,
  BreakdownOutput,
  IncrementalBreakdownSchema,
  IncrementalSubtask,
} from '../types';

export interface BreakdownTaskInput {
  repoId: string;
  goal: string;
  /** Firebase Auth UID of the requester, for `createdBy`. */
  requestedBy: string;
  /**
   * W6: optional human-readable English language NAME (e.g. "Traditional
   * Chinese") the client derives from the app locale. When set, the generated
   * task titles/descriptions are forced into that language; absent/empty → the
   * model follows the spec's own language (the base prompt rule).
   */
  language?: string;
}

export interface BreakdownTaskResult {
  /** Final subtasks with REAL `taskId` strings (already written to Firestore). */
  subtasks: Array<{
    id: string;
    title: string;
    description: string;
    dependsOn: string[];
    estimatedHours: number;
  }>;
}

/** A subtask ready to persist (deps already resolved to real taskIds). */
interface ResolvedSubtask {
  id: string;
  title: string;
  description: string;
  dependsOn: string[];
  estimatedHours: number;
}

export async function breakdownTaskFlow(
  input: BreakdownTaskInput,
): Promise<BreakdownTaskResult> {
  const { repoId, goal, requestedBy, language } = input;

  // ---- Step 1: fetchProjectContext (Firestore only, NO GitHub) -------------
  // Context = the pasted SPEC.md (`goal`) + light repo info (name/desc).
  logger.info('Step 1: fetch project context', { repoId });
  const repoRef = db.doc(`apps/gitsync/repos/${repoId}`);
  const repoSnap = await repoRef.get();
  if (!repoSnap.exists) {
    throw new HttpsError('not-found', `repo ${repoId} not found`);
  }
  const repo = repoSnap.data() ?? {};

  // ---- Step 1b: auto-detect EMPTY vs NON-EMPTY repo (prd D1) ----------------
  // One cheap read: does the repo already have ANY task? Empty → first-pass
  // single-shot; non-empty → incremental agentic loop.
  const existingProbe = await db
    .collection(`apps/gitsync/repos/${repoId}/tasks`)
    .limit(1)
    .get();
  const hasExistingTasks = !existingProbe.empty;

  let resolved: ResolvedSubtask[];
  if (hasExistingTasks) {
    logger.info('breakdownTaskFlow: incremental path (repo has tasks)', { repoId });
    resolved = await incrementalBreakdown(repoId, goal, language);
  } else {
    logger.info('breakdownTaskFlow: first-pass path (empty repo)', { repoId });
    resolved = await firstPassBreakdown(repoId, goal, repo, language);
  }

  // ---- Final: transactional batch write ------------------------------------
  // NOTE: the flow does NOT touch `isBreakingDown` — the handler owns that lock
  // and releases it in `finally`.
  logger.info('Step 6: writing task docs', { repoId, count: resolved.length });
  const now = FieldValue.serverTimestamp();
  const tasksCol = db.collection(`apps/gitsync/repos/${repoId}/tasks`);
  const batch = db.batch();
  for (const s of resolved) {
    batch.set(tasksCol.doc(s.id), {
      title: s.title,
      description: s.description,
      status: 'todo',
      assigneeId: null,
      dependsOn: s.dependsOn,
      githubIssueNumber: null,
      linkedPRNumbers: [],
      acceptanceCriteria: [],
      handoffDoc: null,
      source: 'ai_breakdown',
      parentTaskId: null,
      createdBy: requestedBy,
      createdAt: now,
      updatedAt: now,
      estimatedHours: s.estimatedHours,
    });
  }
  await batch.commit();

  return {
    subtasks: resolved.map((s) => ({
      id: s.id,
      title: s.title,
      description: s.description,
      dependsOn: s.dependsOn,
      estimatedHours: s.estimatedHours,
    })),
  };
}

// ===========================================================================
// PATH A — first-pass single-shot breakdown (EMPTY repo). UNCHANGED behavior.
// ===========================================================================

async function firstPassBreakdown(
  repoId: string,
  goal: string,
  repo: Record<string, unknown>,
  language?: string,
): Promise<ResolvedSubtask[]> {
  // Best-effort: pull the repo's in-repo planning docs (.trellis / AGENTS.md /
  // CLAUDE.md / .claude / docs) so the breakdown knows what work already exists
  // instead of re-decomposing it. An empty result (no docs, no token) leaves the
  // "newly imported project" framing unchanged. Never throws.
  const repoDocs = await readRepoPlanningDocs(repoId);
  const hasDocs = repoDocs.content.trim().length > 0;

  // Best-effort: prepend the accumulated project brief as a stable, cache-friendly
  // prefix (empty brief → '' → byte-identical prompt).
  const briefPrefix = formatBriefForPrompt(await readProjectBrief(repoId));

  const projectContext = [
    briefPrefix || undefined,
    hasDocs ? repoDocs.content : undefined,
    `Repository: ${repo.name ?? repoId}`,
    repo.description ? `Description: ${repo.description}` : undefined,
    hasDocs
      ? undefined
      : 'This is a newly imported project — there are no existing tasks yet.',
  ]
    .filter(Boolean)
    .join('\n');

  // ---- Step 2: structured-output breakdown via OpenAI ----------------------
  logger.info('Step 2: call OpenAI for breakdown', { repoId });
  const openai = getOpenAI();
  const messages: Array<{ role: 'system' | 'user' | 'assistant'; content: string }> = [
    { role: 'system', content: breakdownTaskSystem(language) },
    { role: 'user', content: breakdownTaskUser({ projectContext, goal }) },
  ];

  const completion = await openai.beta.chat.completions.parse({
    model: MODELS.reasoning,
    messages,
    response_format: zodResponseFormat(BreakdownOutputSchema, 'breakdown'),
  });
  let parsed: BreakdownOutput | null =
    (completion.choices[0]?.message?.parsed as BreakdownOutput | null) ?? null;
  if (!parsed) {
    throw new HttpsError(
      'internal',
      'AI did not return a valid breakdown (refused or empty).',
    );
  }

  // ---- Step 3 / 3b: cycle detection + single re-prompt ---------------------
  let cycles = detectCycles(parsed.subtasks);
  if (cycles.length > 0) {
    logger.warn('Step 3: cycle detected, re-prompting once', { repoId, cycles });
    messages.push({
      role: 'assistant',
      content: JSON.stringify(parsed),
    });
    messages.push({
      role: 'user',
      content:
        'Your previous response contained circular dependencies among these ' +
        `subtask indices: ${JSON.stringify(cycles)}. ` +
        'Regenerate the breakdown so that dependsOn forms a directed acyclic ' +
        'graph (no cycles). Return JSON matching the schema.',
    });

    const retry = await openai.beta.chat.completions.parse({
      model: MODELS.reasoning,
      messages,
      response_format: zodResponseFormat(BreakdownOutputSchema, 'breakdown'),
    });
    parsed = (retry.choices[0]?.message?.parsed as BreakdownOutput | null) ?? null;
    if (!parsed) {
      throw new HttpsError(
        'internal',
        'AI did not return a valid breakdown on re-prompt.',
      );
    }
    cycles = detectCycles(parsed.subtasks);
    if (cycles.length > 0) {
      throw new HttpsError('internal', 'AI produced cyclic dependencies twice');
    }
  }

  const subtasks = parsed.subtasks;

  // ---- Step 4: pre-generate Firestore doc IDs ------------------------------
  const tasksCol = db.collection(`apps/gitsync/repos/${repoId}/tasks`);
  const ids = subtasks.map(() => tasksCol.doc().id);

  // ---- Step 5: translate dependsOn 0-based indices → real taskIds ----------
  return subtasks.map((s, i) => ({
    id: ids[i],
    title: s.title,
    description: s.description,
    estimatedHours: s.estimatedHours,
    dependsOn: s.dependsOn
      .filter((idx) => idx >= 0 && idx < ids.length)
      .map((idx) => ids[idx]),
  }));
}

// ===========================================================================
// PATH B — incremental agentic breakdown (NON-EMPTY repo). prd D1/D3/D5.
// ===========================================================================

const MAX_ROUNDS = 5;

const INCREMENTAL_TOOLS: OpenAI.Chat.Completions.ChatCompletionTool[] = [
  {
    type: 'function',
    function: {
      name: 'listExistingTaskTitles',
      description:
        'Page through the repo\'s EXISTING tasks ({taskId,title,status}). Call ' +
        'this first to learn the current plan. Pass `cursor` (the nextCursor ' +
        'from a prior page) to continue, and/or `status` to filter.',
      parameters: {
        type: 'object',
        properties: {
          status: {
            type: 'string',
            description: 'Optional status filter (e.g. todo / in_progress / done).',
          },
          cursor: {
            type: 'string',
            description: 'nextCursor from a previous page; omit for the first page.',
          },
        },
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchExistingTasks',
      description:
        'Keyword-search existing tasks related to a topic. Returns ' +
        '{taskId,title,status,dependsOn} so you can dedup and wire dependencies ' +
        'to them. Use the returned taskId in dependsOnExisting.',
      parameters: {
        type: 'object',
        properties: {
          query: { type: 'string', description: 'Search terms.' },
          limit: { type: 'number', description: 'Max results (default 10).' },
        },
        required: ['query'],
        additionalProperties: false,
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'searchPastCommits',
      description:
        'Semantic search of the real commit history — to spot work already ' +
        'done even if no task is marked complete (grounding).',
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
      name: 'readRepoPlanningDocs',
      description:
        "Read the repo's in-repo planning docs (.trellis tasks/prd, " +
        'AGENTS.md/CLAUDE.md, docs). Cheap (cached).',
      parameters: { type: 'object', properties: {}, additionalProperties: false },
    },
  },
  {
    type: 'function',
    function: {
      name: 'submitBreakdown',
      description:
        'Submit ONLY the missing subtasks and END the loop. Each subtask: ' +
        '{title, description, estimatedHours, dependsOnNew (0-based indices ' +
        'into this array), dependsOnExisting (real existing taskIds)}.',
      parameters: {
        type: 'object',
        properties: {
          subtasks: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                title: { type: 'string' },
                description: { type: 'string' },
                estimatedHours: { type: 'number' },
                dependsOnNew: {
                  type: 'array',
                  items: { type: 'number' },
                  description: '0-based indices of prerequisites in this same array.',
                },
                dependsOnExisting: {
                  type: 'array',
                  items: { type: 'string' },
                  description: 'Real taskIds of existing tasks this depends on.',
                },
              },
              required: ['title', 'description', 'estimatedHours'],
              additionalProperties: false,
            },
          },
        },
        required: ['subtasks'],
        additionalProperties: false,
      },
    },
  },
];

async function incrementalBreakdown(
  repoId: string,
  goal: string,
  language?: string,
): Promise<ResolvedSubtask[]> {
  // Best-effort project-brief prefix (stable; empty → '' → no behavior change).
  const briefPrefix = formatBriefForPrompt(await readProjectBrief(repoId));

  const openai = getOpenAI();
  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: 'system', content: incrementalBreakdownSystem(language) + briefPrefix },
    { role: 'user', content: incrementalBreakdownUser(goal) },
  ];

  // One re-prompt budget for a cyclic submission (mirrors the first-pass path).
  let cycleRetryUsed = false;

  for (let round = 0; round < MAX_ROUNDS; round++) {
    logger.info('incrementalBreakdown: agentic round', { repoId, round });

    const completion = await openai.chat.completions.create({
      model: MODELS.reasoning,
      messages,
      tools: INCREMENTAL_TOOLS,
      tool_choice: 'auto',
    });

    const choice = completion.choices[0]?.message;
    if (!choice) throw new HttpsError('internal', 'OpenAI returned no message');
    messages.push(choice);

    const toolCalls = choice.tool_calls ?? [];
    if (toolCalls.length === 0) {
      // Answered without a tool — nudge it to submit, then retry.
      messages.push({
        role: 'user',
        content: 'You must call submitBreakdown with the missing subtasks.',
      });
      continue;
    }

    // Look for the terminator first.
    const submitCall = toolCalls.find(
      (c) => c.type === 'function' && c.function.name === 'submitBreakdown',
    );
    if (submitCall && submitCall.type === 'function') {
      // The model may batch read tools alongside submitBreakdown in one turn.
      // OpenAI requires EVERY tool_call in the assistant message to get a
      // `role:'tool'` reply before the next request — otherwise any `continue`
      // below (malformed args / cycle re-prompt) sends an assistant turn with
      // dangling tool_call_ids and the API 400s. So answer the sibling read
      // calls first; only then handle the terminator.
      const siblings = toolCalls.filter((c) => c.id !== submitCall.id);
      const siblingResults = await Promise.all(
        siblings.map(async (call) => {
          if (call.type !== 'function') {
            return { id: call.id, content: 'unsupported tool call' };
          }
          const content = await runIncrementalTool(
            repoId,
            call.function.name,
            safeParse(call.function.arguments),
          );
          return { id: call.id, content };
        }),
      );
      for (const r of siblingResults) {
        messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
      }

      const parsed = IncrementalBreakdownSchema.safeParse(
        safeParse(submitCall.function.arguments),
      );
      if (!parsed.success) {
        // Malformed args — feed the error back and let the model retry.
        messages.push({
          role: 'tool',
          tool_call_id: submitCall.id,
          content:
            'Error: submitBreakdown arguments did not match the schema. ' +
            'Each subtask needs title, description, estimatedHours, ' +
            'dependsOnNew[], dependsOnExisting[]. Try again.',
        });
        continue;
      }

      const resolved = await resolveAndCheck(
        repoId,
        parsed.data.subtasks,
        submitCall.id,
        messages,
        cycleRetryUsed,
      );
      if (resolved.kind === 'ok') return resolved.subtasks;
      if (resolved.kind === 'cycle-retry') {
        cycleRetryUsed = true;
        continue; // messages already carry the cycle feedback
      }
      // kind === 'cycle-fail' → cyclic twice.
      throw new HttpsError(
        'internal',
        'AI produced cyclic dependencies twice (existing + new graph)',
      );
    }

    // No submit this round — run the read tools in parallel, feed results back.
    const results = await Promise.all(
      toolCalls.map(async (call) => {
        if (call.type !== 'function') {
          return { id: call.id, content: 'unsupported tool call' };
        }
        const content = await runIncrementalTool(
          repoId,
          call.function.name,
          safeParse(call.function.arguments),
        );
        return { id: call.id, content };
      }),
    );
    for (const r of results) {
      messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
    }
  }

  // Ran out of rounds without a valid submit → throw (never silently write).
  logger.warn('incrementalBreakdown: round limit hit without submitBreakdown', {
    repoId,
  });
  throw new HttpsError(
    'internal',
    'AI did not submit a breakdown within the round limit.',
  );
}

type ResolveResult =
  | { kind: 'ok'; subtasks: ResolvedSubtask[] }
  | { kind: 'cycle-retry' }
  | { kind: 'cycle-fail' };

/**
 * Pre-generate ids for the new subtasks, resolve dependsOnNew (index) +
 * dependsOnExisting (real taskIds, dropping unknown refs), then cycle-check the
 * COMBINED existing+new graph. On a cycle, append feedback for one re-prompt
 * (returning `cycle-retry`); a second cycle returns `cycle-fail`.
 */
async function resolveAndCheck(
  repoId: string,
  subtasks: IncrementalSubtask[],
  submitCallId: string,
  messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[],
  cycleRetryUsed: boolean,
): Promise<ResolveResult> {
  // Existing graph (real read — needed for the full cycle check). NOT
  // best-effort: a broken read must not let us write on an unverified graph.
  const existingGraph = await readExistingTaskGraph(repoId);
  const existingIds = new Set(existingGraph.keys());

  // Pre-generate ids for the new batch.
  const tasksCol = db.collection(`apps/gitsync/repos/${repoId}/tasks`);
  const newIds = subtasks.map(() => tasksCol.doc().id);

  const resolved: ResolvedSubtask[] = subtasks.map((s, i) => {
    const fromNew = (Array.isArray(s.dependsOnNew) ? s.dependsOnNew : [])
      .filter((idx) => idx >= 0 && idx < newIds.length && idx !== i)
      .map((idx) => newIds[idx]);
    const fromExisting = (Array.isArray(s.dependsOnExisting) ? s.dependsOnExisting : [])
      .filter((id) => {
        const ok = existingIds.has(id);
        if (!ok) {
          logger.warn('incrementalBreakdown: dropping unknown dependsOnExisting', {
            repoId,
            taskId: id,
          });
        }
        return ok;
      });
    // Dedupe while preserving order.
    const dependsOn = [...new Set([...fromNew, ...fromExisting])];
    return {
      id: newIds[i],
      title: s.title,
      description: s.description,
      estimatedHours: s.estimatedHours,
      dependsOn,
    };
  });

  // Build the combined graph keyed by taskId and check for cycles.
  const combined = new Map<string, string[]>(existingGraph);
  for (const r of resolved) combined.set(r.id, r.dependsOn);
  const cyclic = hasCycleById(combined);

  if (cyclic) {
    if (cycleRetryUsed) return { kind: 'cycle-fail' };
    logger.warn('incrementalBreakdown: cycle in combined graph, re-prompting once', {
      repoId,
    });
    messages.push({
      role: 'tool',
      tool_call_id: submitCallId,
      content:
        'Error: your subtasks created a circular dependency once combined with ' +
        'the existing tasks. Fix dependsOnNew / dependsOnExisting so the whole ' +
        'graph is acyclic, then call submitBreakdown again.',
    });
    return { kind: 'cycle-retry' };
  }

  return { kind: 'ok', subtasks: resolved };
}

/** Execute one incremental read tool, returning a JSON string for the model. */
async function runIncrementalTool(
  repoId: string,
  name: string,
  args: Record<string, unknown>,
): Promise<string> {
  switch (name) {
    case 'listExistingTaskTitles':
      return JSON.stringify(
        await listExistingTaskTitles(repoId, {
          status: typeof args.status === 'string' ? args.status : undefined,
          cursor: typeof args.cursor === 'string' ? args.cursor : undefined,
        }),
      );
    case 'searchExistingTasks':
      return JSON.stringify(
        await searchExistingTasks(
          repoId,
          String(args.query ?? ''),
          typeof args.limit === 'number' ? args.limit : undefined,
        ),
      );
    case 'searchPastCommits':
      return JSON.stringify(
        await searchPastCommits(
          repoId,
          String(args.query ?? ''),
          typeof args.limit === 'number' ? args.limit : 8,
        ),
      );
    case 'readRepoPlanningDocs':
      return JSON.stringify((await readRepoPlanningDocs(repoId)).content);
    default:
      return `Error: unknown tool ${name}`;
  }
}

/** Parse a tool-call arguments JSON string, tolerating malformed input. */
function safeParse(raw: string | undefined): Record<string, unknown> {
  if (!raw) return {};
  try {
    return JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return {};
  }
}

// ---- Helpers (exported so tests can unit-test them in isolation) -----------

/**
 * Returns the indices of every cycle in the dependency graph (DFS).
 * Empty array = no cycles. Used by the first-pass (index-based) path.
 */
export function detectCycles(
  subtasks: Array<{ dependsOn: number[] }>,
): number[][] {
  const cycles: number[][] = [];
  const WHITE = 0,
    GRAY = 1,
    BLACK = 2;
  const color = new Array<number>(subtasks.length).fill(WHITE);
  const stack: number[] = [];

  function dfs(i: number) {
    color[i] = GRAY;
    stack.push(i);
    for (const dep of subtasks[i].dependsOn) {
      if (dep < 0 || dep >= subtasks.length) continue;
      if (color[dep] === GRAY) {
        cycles.push([...stack.slice(stack.indexOf(dep)), dep]);
      } else if (color[dep] === WHITE) {
        dfs(dep);
      }
    }
    color[i] = BLACK;
    stack.pop();
  }

  for (let i = 0; i < subtasks.length; i++) {
    if (color[i] === WHITE) dfs(i);
  }
  return cycles;
}

/**
 * Cycle check for a graph keyed by taskId (the COMBINED existing+new graph of
 * the incremental path). Edges that point at unknown ids are ignored. Returns
 * true iff the graph has at least one cycle.
 */
export function hasCycleById(graph: Map<string, string[]>): boolean {
  const WHITE = 0,
    GRAY = 1,
    BLACK = 2;
  const color = new Map<string, number>();
  for (const id of graph.keys()) color.set(id, WHITE);

  const dfs = (id: string): boolean => {
    color.set(id, GRAY);
    for (const dep of graph.get(id) ?? []) {
      if (!graph.has(dep)) continue; // unknown ref — not part of the graph
      const c = color.get(dep);
      if (c === GRAY) return true;
      if (c === WHITE && dfs(dep)) return true;
    }
    color.set(id, BLACK);
    return false;
  };

  for (const id of graph.keys()) {
    if (color.get(id) === WHITE && dfs(id)) return true;
  }
  return false;
}

// Re-exports kept here so handler files have one short import:
export { BreakdownOutputSchema, getOpenAI, MODELS, breakdownTaskSystem, breakdownTaskUser, zodResponseFormat, db, logger };
export type { BreakdownOutput };
