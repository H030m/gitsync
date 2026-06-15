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
import { recallForPrompt } from '../tools/memorySearch';
import { writeObservation } from '../tools/memoryWrite';
import { searchPastCommits } from '../tools/dailyIntel';
import {
  listExistingTaskTitles,
  searchExistingTasks,
  readExistingTaskGraph,
} from '../tools/breakdownTools';
import {
  startRun,
  appendStep,
  finishRun,
  TRACE_LABELS,
} from '../tools/agentTrace';
import { assignTaskFlow } from './assignTask';
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
  /** Client-generated agent-trace doc id; absent → trace is a no-op. */
  runId?: string;
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
  const { repoId, goal, requestedBy, language, runId } = input;

  // Best-effort agent trace (no-op without a runId).
  await startRun(repoId, runId, 'breakdownTask');

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
  try {
  if (hasExistingTasks) {
    logger.info('breakdownTaskFlow: incremental path (repo has tasks)', { repoId });
    resolved = await incrementalBreakdown(repoId, goal, language, runId);
  } else {
    logger.info('breakdownTaskFlow: first-pass path (empty repo)', { repoId });
    await appendStep(repoId, runId, TRACE_LABELS.breakdownGenerate);
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

  // Auto-assign ROOT tasks (no prerequisites) right away — they are ready to
  // start, so the user shouldn't have to assign them by hand. Downstream tasks
  // are still auto-assigned later by onTaskUpdated when their prerequisites
  // finish. Best-effort + parallel: a failure just leaves that task unassigned
  // (the user can assign it manually) and never fails the breakdown.
  const rootTasks = resolved.filter((s) => s.dependsOn.length === 0);
  if (rootTasks.length > 0) {
    logger.info('breakdownTaskFlow: auto-assigning root tasks', {
      repoId,
      count: rootTasks.length,
    });
    await Promise.allSettled(
      rootTasks.map((s) =>
        assignTaskFlow({ repoId, taskId: s.id }).catch((err) => {
          logger.warn('breakdownTaskFlow: auto-assign root failed (best-effort)', {
            repoId,
            taskId: s.id,
            err: String(err),
          });
        }),
      ),
    );
  }

  // Best-effort: record what was broken down so future flows can recall it.
  const topTitles = resolved.slice(0, 3).map((s) => s.title).join('、');
  writeObservation(repoId, {
    content: `Goal "${goal.slice(0, 50)}" 拆成 ${resolved.length} 個子任務：${topTitles}`,
    category: 'project_state',
    sourceFlow: 'breakdownTask',
    tags: ['breakdown'],
  }).catch(() => {});

  await finishRun(repoId, runId, 'done');
  return {
    subtasks: resolved.map((s) => ({
      id: s.id,
      title: s.title,
      description: s.description,
      dependsOn: s.dependsOn,
      estimatedHours: s.estimatedHours,
    })),
  };
  } catch (err) {
    await finishRun(repoId, runId, 'error');
    throw err;
  }
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
  const brief = await readProjectBrief(repoId);
  const briefPrefix = formatBriefForPrompt(brief);

  // Best-effort active recall using the goal text (empty when no observations exist).
  const memoryContext = await recallForPrompt(repoId, {
    query: goal,
    briefContent: brief?.content,
  });

  const projectContext = [
    briefPrefix || undefined,
    memoryContext || undefined,
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
    model: MODELS.fast,
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
  // Strip self-references / out-of-range indices first: a task depending on its
  // OWN index is the model's most common (and trivially removable) DAG
  // violation — treat it as noise, not a fatal cycle (mirrors the incremental
  // path's `idx !== i` filter). Only genuine multi-node cycles re-prompt.
  sanitizeDependsOn(parsed.subtasks);
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
      model: MODELS.fast,
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
    sanitizeDependsOn(parsed.subtasks);
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
  runId?: string,
): Promise<ResolvedSubtask[]> {
  // Best-effort project-brief prefix (stable; empty → '' → no behavior change).
  const brief = await readProjectBrief(repoId);
  const briefPrefix = formatBriefForPrompt(brief);

  // Best-effort active recall using the goal text (empty when no observations exist).
  const memoryContext = await recallForPrompt(repoId, {
    query: goal,
    briefContent: brief?.content,
  });

  const openai = getOpenAI();
  const messages: OpenAI.Chat.Completions.ChatCompletionMessageParam[] = [
    { role: 'system', content: incrementalBreakdownSystem(language) + briefPrefix + memoryContext },
    { role: 'user', content: incrementalBreakdownUser(goal) },
  ];

  // One re-prompt budget for a cyclic submission (mirrors the first-pass path).
  let cycleRetryUsed = false;

  for (let round = 0; round < MAX_ROUNDS; round++) {
    logger.info('incrementalBreakdown: agentic round', { repoId, round });

    const completion = await openai.chat.completions.create({
      model: MODELS.fast,
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
          const args = safeParse(call.function.arguments);
          const { content, resultCount } = await runIncrementalTool(
            repoId,
            call.function.name,
            args,
          );
          logToolCall(repoId, round, call.function.name, args, resultCount);
          return { id: call.id, content };
        }),
      );
      for (const r of siblingResults) {
        messages.push({ role: 'tool', tool_call_id: r.id, content: r.content });
      }

      const submitArgs = safeParse(submitCall.function.arguments);
      const parsed = IncrementalBreakdownSchema.safeParse(submitArgs);
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

      logSubmit(repoId, round, parsed.data.subtasks);
      await appendStep(repoId, runId, TRACE_LABELS.submitBreakdown);

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
        const args = safeParse(call.function.arguments);
        const { content, resultCount } = await runIncrementalTool(
          repoId,
          call.function.name,
          args,
        );
        logToolCall(repoId, round, call.function.name, args, resultCount);
        return { id: call.id, content, tool: call.function.name as string };
      }),
    );
    // Best-effort trace: one step per tool this round.
    const traceLabels = results
      .filter((r): r is typeof r & { tool: string } => 'tool' in r)
      .map((r) => toolTraceLabel(r.tool));
    if (traceLabels.length > 0) {
      await appendStep(repoId, runId, traceLabels);
    }
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

/**
 * Execute one incremental read tool, returning the JSON string for the model
 * plus a `resultCount` (array/page length, for observability logging). Errors
 * are already swallowed inside the tools (best-effort), so this never throws.
 */
async function runIncrementalTool(
  repoId: string,
  name: string,
  args: Record<string, unknown>,
): Promise<{ content: string; resultCount: number }> {
  switch (name) {
    case 'listExistingTaskTitles': {
      const page = await listExistingTaskTitles(repoId, {
        status: typeof args.status === 'string' ? args.status : undefined,
        cursor: typeof args.cursor === 'string' ? args.cursor : undefined,
      });
      return { content: JSON.stringify(page), resultCount: page.tasks.length };
    }
    case 'searchExistingTasks': {
      const hits = await searchExistingTasks(
        repoId,
        String(args.query ?? ''),
        typeof args.limit === 'number' ? args.limit : undefined,
      );
      return { content: JSON.stringify(hits), resultCount: hits.length };
    }
    case 'searchPastCommits': {
      const commits = await searchPastCommits(
        repoId,
        String(args.query ?? ''),
        typeof args.limit === 'number' ? args.limit : 8,
      );
      const count = Array.isArray(commits) ? commits.length : 0;
      return { content: JSON.stringify(commits), resultCount: count };
    }
    case 'readRepoPlanningDocs': {
      const content = (await readRepoPlanningDocs(repoId)).content;
      return { content: JSON.stringify(content), resultCount: content ? 1 : 0 };
    }
    default:
      return { content: `Error: unknown tool ${name}`, resultCount: 0 };
  }
}

/**
 * Best-effort per-tool-call observability log (prd 06-15). Records WHICH tool the
 * model called this round, a COMPACT arg summary (never full content), and how
 * many rows it returned — so cloud logs reveal whether the agent actually
 * explored existing tasks. Never throws / never changes control flow.
 */
function logToolCall(
  repoId: string,
  round: number,
  tool: string,
  args: Record<string, unknown>,
  resultCount: number,
): void {
  try {
    let summary: Record<string, unknown> = {};
    switch (tool) {
      case 'listExistingTaskTitles':
        summary = {
          status: typeof args.status === 'string' ? args.status : undefined,
          hasCursor: !!args.cursor,
        };
        break;
      case 'searchExistingTasks':
      case 'searchPastCommits':
        summary = {
          query: typeof args.query === 'string' ? args.query : undefined,
          limit: typeof args.limit === 'number' ? args.limit : undefined,
        };
        break;
      case 'readRepoPlanningDocs':
      default:
        summary = {};
        break;
    }
    logger.info('incrementalBreakdown: tool call', {
      repoId,
      round,
      tool,
      args: summary,
      resultCount,
    });
  } catch {
    /* logging is best-effort; never let it affect the flow */
  }
}

/**
 * Best-effort submit-visibility log (prd 06-15): how many new subtasks were
 * submitted and how many dependency edges point at NEW vs EXISTING tasks. Makes
 * "did the new tasks depend on existing ones" directly visible in cloud logs.
 */
function logSubmit(
  repoId: string,
  round: number,
  subtasks: IncrementalSubtask[],
): void {
  try {
    let totalDependsOnNew = 0;
    let totalDependsOnExisting = 0;
    for (const s of subtasks) {
      if (Array.isArray(s.dependsOnNew)) totalDependsOnNew += s.dependsOnNew.length;
      if (Array.isArray(s.dependsOnExisting)) {
        totalDependsOnExisting += s.dependsOnExisting.length;
      }
    }
    logger.info('incrementalBreakdown: submit', {
      repoId,
      round,
      subtaskCount: subtasks.length,
      totalDependsOnNew,
      totalDependsOnExisting,
    });
  } catch {
    /* logging is best-effort; never let it affect the flow */
  }
}

/** Parse a tool-call arguments JSON string, tolerating malformed input. */
/** Map an incremental breakdown tool name to a user-visible trace label. */
function toolTraceLabel(tool: string): string {
  switch (tool) {
    case 'listExistingTaskTitles': return TRACE_LABELS.listExistingTaskTitles;
    case 'searchExistingTasks': return TRACE_LABELS.searchExistingTasks;
    case 'searchPastCommits': return TRACE_LABELS.searchPastCommits;
    case 'readRepoPlanningDocs': return TRACE_LABELS.readRepoPlanningDocs;
    case 'submitBreakdown': return TRACE_LABELS.submitBreakdown;
    default: return tool;
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

// ---- Helpers (exported so tests can unit-test them in isolation) -----------

/**
 * Normalize each subtask's `dependsOn` IN PLACE: drop out-of-range indices,
 * remove self-references (a task can never depend on itself), and dedupe.
 * Self-loops are the model's most common DAG violation; stripping them keeps an
 * otherwise-valid breakdown from failing the cycle check. Mirrors the
 * incremental path's `idx !== i` filter.
 */
export function sanitizeDependsOn(
  subtasks: Array<{ dependsOn: number[] }>,
): void {
  subtasks.forEach((s, i) => {
    s.dependsOn = [
      ...new Set(
        (Array.isArray(s.dependsOn) ? s.dependsOn : []).filter(
          (idx) => idx >= 0 && idx < subtasks.length && idx !== i,
        ),
      ),
    ];
  });
}

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
