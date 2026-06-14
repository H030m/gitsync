// Unit tests for breakdownTaskFlow + detectCycles.
//
// Boundary mocks (same style as addRepo.test.ts):
//   - firebase-functions/v2/https → HttpsError captures `code`.
//   - firebase-functions/v2 → logger no-op.
//   - firebase-admin/firestore → FieldValue.serverTimestamp sentinel.
//   - ../admin → hand-rolled fake Firestore (doc/get/collection/batch).
//   - ../config → getOpenAI returns a mock whose parse() is queued per-test.
//   - ../prompts/breakdownTask → real prompts are fine; left unmocked.

// ---- Mocks ----------------------------------------------------------------

class FakeHttpsError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'HttpsError';
  }
}

jest.mock('firebase-functions/v2/https', () => ({
  HttpsError: FakeHttpsError,
}));

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

jest.mock('firebase-admin/firestore', () => ({
  FieldValue: {
    serverTimestamp: () => '__serverTimestamp__',
  },
}));

// ---- Fake Firestore -------------------------------------------------------
//
// store: docPath -> data. A collection's doc() with no id auto-generates a
// monotonic id so tests can predict them (`t0`, `t1`, ...). doc(id) targets a
// specific path. batch.set() records writes, applied on commit().

interface FakeDoc {
  exists: boolean;
  data: () => Record<string, unknown> | undefined;
}

const store = new Map<string, Record<string, unknown>>();
const batchWrites: Array<{ path: string; data: Record<string, unknown> }> = [];
let idCounter = 0;

function makeDocRef(path: string) {
  return {
    path,
    id: path.split('/').pop() as string,
    async get(): Promise<FakeDoc> {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
  };
}

// Direct children of a collection path (no nested subcollection docs).
function childDocsOf(colPath: string): Array<[string, Record<string, unknown>]> {
  return [...store.entries()].filter(
    ([p]) =>
      p.startsWith(`${colPath}/`) &&
      p.slice(colPath.length + 1).indexOf('/') === -1,
  );
}

// A query supporting the chain used by the flow + breakdownTools:
// .limit(n).get() (empty-repo probe), .orderBy().limit().startAfter().get(),
// and a plain .get() (readExistingTaskGraph). Ordered by doc id (__name__).
function makeQuery(
  colPath: string,
  opts: { limit?: number; after?: string } = {},
) {
  const run = () => {
    let rows = childDocsOf(colPath).sort(([a], [b]) =>
      a < b ? -1 : a > b ? 1 : 0,
    );
    if (opts.after) {
      const afterPath = `${colPath}/${opts.after}`;
      rows = rows.filter(([p]) => p > afterPath);
    }
    if (opts.limit !== undefined) rows = rows.slice(0, opts.limit);
    return rows;
  };
  const snap = () => {
    const rows = run();
    return {
      empty: rows.length === 0,
      docs: rows.map(([p, d]) => ({ id: p.split('/').pop() as string, data: () => d })),
    };
  };
  return {
    orderBy: () => makeQuery(colPath, opts),
    limit: (n: number) => makeQuery(colPath, { ...opts, limit: n }),
    startAfter: (cursor: string) => makeQuery(colPath, { ...opts, after: cursor }),
    async get() {
      return snap();
    },
  };
}

function makeCollectionRef(basePath: string) {
  const q = makeQuery(basePath, {});
  return {
    doc: (id?: string) => {
      const docId = id ?? `t${idCounter++}`;
      return makeDocRef(`${basePath}/${docId}`);
    },
    orderBy: q.orderBy,
    limit: q.limit,
    get: q.get,
  };
}

const fakeDb = {
  doc: (path: string) => makeDocRef(path),
  collection: (path: string) => makeCollectionRef(path),
  batch: () => ({
    set(ref: { path: string }, data: Record<string, unknown>) {
      batchWrites.push({ path: ref.path, data });
    },
    async commit() {
      for (const w of batchWrites) store.set(w.path, w.data);
    },
  }),
};

jest.mock('../admin', () => ({
  db: fakeDb,
  REGION: 'asia-east1',
}));

// ---- Fake OpenAI ----------------------------------------------------------

const parseQueue: Array<{ parsed: unknown }> = [];
const mockParse = jest.fn(async () => {
  const next = parseQueue.shift();
  return { choices: [{ message: { parsed: next?.parsed ?? null } }] };
});

// Agentic (incremental) path uses chat.completions.create; script per test.
const createQueue: Array<{ message: unknown }> = [];
const mockCreate = jest.fn(async () => {
  const next = createQueue.shift();
  if (!next) throw new Error('createQueue empty — test under-scripted OpenAI');
  return { choices: [next] };
});

jest.mock('../config', () => ({
  getOpenAI: () => ({
    beta: { chat: { completions: { parse: mockParse } } },
    chat: { completions: { create: mockCreate } },
  }),
  MODELS: { reasoning: 'gpt-4o', fast: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
}));

// Mock dailyIntel.searchPastCommits so the test never pulls in tools/embedding
// → openai (ESM). Scriptable per test; defaults to [].
let pastCommitsResult: unknown[] = [];
const mockSearchPastCommits = jest.fn(async (..._args: unknown[]) => pastCommitsResult);
jest.mock('../tools/dailyIntel', () => ({
  searchPastCommits: (...args: unknown[]) => mockSearchPastCommits(...args),
}));

// zodResponseFormat from openai pulls in zod; keep it but it's harmless. The
// real helper is used so the call shape matches production.

// Mock tools/repoDocs so the flow's Step-1 call is scriptable per test and the
// test never pulls in githubClient → @octokit/rest (ESM, jest can't parse it).
let repoDocsResult: {
  content: string;
  summary: string;
  source: string;
  cached: boolean;
} = { content: '', summary: 'no GitHub docs available', source: 'none', cached: false };
const mockReadRepoPlanningDocs = jest.fn((_repoId: string) =>
  Promise.resolve(repoDocsResult),
);
jest.mock('../tools/repoDocs', () => ({
  readRepoPlanningDocs: (repoId: string) => mockReadRepoPlanningDocs(repoId),
}));

// Import after mocks.
import { logger } from 'firebase-functions/v2';
import { breakdownTaskFlow, detectCycles, hasCycleById } from '../flows/breakdownTask';
import {
  listExistingTaskTitles,
  searchExistingTasks,
} from '../tools/breakdownTools';
import { incrementalBreakdownSystem } from '../prompts/breakdownTask';
import { GITSYNC_BASE_SYSTEM } from '../prompts/baseSystem';

function seedRepo(repoId: string, data: Record<string, unknown>) {
  store.set(`apps/gitsync/repos/${repoId}`, data);
}

function seedTask(repoId: string, taskId: string, data: Record<string, unknown>) {
  store.set(`apps/gitsync/repos/${repoId}/tasks/${taskId}`, {
    title: taskId,
    status: 'todo',
    dependsOn: [],
    ...data,
  });
}

/** The `content` of the user message in the first OpenAI parse() call. */
function firstUserMessage(): string {
  const call = mockParse.mock.calls[0] as unknown[];
  const arg = call[0] as {
    messages: Array<{ role: string; content: string }>;
  };
  return arg.messages.find((m) => m.role === 'user')!.content;
}

/** Concatenated content of every message sent across all create() calls. */
function allCreateMessages(): Array<{ role: string; content: unknown }> {
  const out: Array<{ role: string; content: unknown }> = [];
  for (const call of mockCreate.mock.calls) {
    const arg = (call as unknown[])[0] as {
      messages: Array<{ role: string; content: unknown }>;
    };
    for (const m of arg.messages) out.push(m);
  }
  return out;
}

/**
 * Find the structured `logger.info(message, fields)` calls whose message
 * matches, returning their `fields` objects (for observability assertions).
 */
function infoLogs(message: string): Array<Record<string, unknown>> {
  return (logger.info as jest.Mock).mock.calls
    .filter((c) => c[0] === message)
    .map((c) => (c[1] ?? {}) as Record<string, unknown>);
}

/** Script an assistant turn that calls a read tool. */
function readToolTurn(name: string, args: Record<string, unknown>, id = 'tc1') {
  return {
    message: {
      role: 'assistant',
      content: null,
      tool_calls: [
        { id, type: 'function', function: { name, arguments: JSON.stringify(args) } },
      ],
    },
  };
}

/** Script an assistant turn that calls submitBreakdown. */
function submitTurn(subtasks: unknown[], id = 'sub1') {
  return {
    message: {
      role: 'assistant',
      content: null,
      tool_calls: [
        {
          id,
          type: 'function',
          function: {
            name: 'submitBreakdown',
            arguments: JSON.stringify({ subtasks }),
          },
        },
      ],
    },
  };
}

/**
 * Script ONE assistant turn that batches a read tool call AND submitBreakdown
 * (the model is allowed to do both in a single message). Exercises the
 * "answer every sibling tool_call before the next round" contract.
 */
function readPlusSubmitTurn(
  read: { name: string; args: Record<string, unknown>; id?: string },
  subtasks: unknown[],
  submitId = 'sub1',
) {
  return {
    message: {
      role: 'assistant',
      content: null,
      tool_calls: [
        {
          id: read.id ?? 'rc1',
          type: 'function',
          function: { name: read.name, arguments: JSON.stringify(read.args) },
        },
        {
          id: submitId,
          type: 'function',
          function: {
            name: 'submitBreakdown',
            arguments: JSON.stringify({ subtasks }),
          },
        },
      ],
    },
  };
}

/**
 * Assert the OpenAI contract: every assistant `tool_call` id that appears in
 * the conversation has a matching `role:'tool'` reply. A dangling tool_call id
 * would make the real API 400 on the next request.
 */
function assertNoDanglingToolCalls() {
  const msgs = allCreateMessages();
  const answered = new Set<string>();
  for (const m of msgs) {
    if (m.role === 'tool') {
      answered.add((m as unknown as { tool_call_id: string }).tool_call_id);
    }
  }
  for (const m of msgs) {
    const calls = (m as unknown as { tool_calls?: Array<{ id: string }> }).tool_calls;
    if (!calls) continue;
    for (const c of calls) {
      // The terminating submit that ENDS the loop (ok) legitimately needs no
      // reply; every other tool_call must be answered before the next turn.
      expect(answered.has(c.id) || c.id === 'sub-final').toBeTruthy();
    }
  }
}

beforeEach(() => {
  store.clear();
  batchWrites.length = 0;
  parseQueue.length = 0;
  createQueue.length = 0;
  idCounter = 0;
  mockParse.mockClear();
  mockCreate.mockClear();
  mockReadRepoPlanningDocs.mockClear();
  mockSearchPastCommits.mockClear();
  (logger.info as jest.Mock).mockClear();
  (logger.warn as jest.Mock).mockClear();
  pastCommitsResult = [];
  repoDocsResult = { content: '', summary: 'no GitHub docs available', source: 'none', cached: false };
});

// ---- detectCycles ---------------------------------------------------------

describe('detectCycles', () => {
  it('returns [] for an acyclic graph', () => {
    expect(
      detectCycles([
        { dependsOn: [] },
        { dependsOn: [0] },
        { dependsOn: [0, 1] },
      ]),
    ).toEqual([]);
  });

  it('detects a direct 2-node cycle', () => {
    const cycles = detectCycles([{ dependsOn: [1] }, { dependsOn: [0] }]);
    expect(cycles.length).toBeGreaterThan(0);
  });

  it('detects a self-loop', () => {
    const cycles = detectCycles([{ dependsOn: [0] }]);
    expect(cycles.length).toBeGreaterThan(0);
  });

  it('ignores out-of-range indices', () => {
    expect(detectCycles([{ dependsOn: [5, -1] }])).toEqual([]);
  });
});

// ---- breakdownTaskFlow ----------------------------------------------------

describe('breakdownTaskFlow', () => {
  it('throws not-found when the repo doc is missing', async () => {
    await expect(
      breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' }),
    ).rejects.toMatchObject({ code: 'not-found' });
  });

  it('throws internal when the model returns no parsed output', async () => {
    seedRepo('x_y', { name: 'x/y' });
    parseQueue.push({ parsed: null });
    await expect(
      breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' }),
    ).rejects.toMatchObject({ code: 'internal' });
  });

  it('happy path: writes N task docs with source ai_breakdown', async () => {
    seedRepo('x_y', { name: 'x/y', description: 'a demo' });
    parseQueue.push({
      parsed: {
        subtasks: [
          { title: 'A', description: 'da', dependsOn: [], estimatedHours: 2 },
          { title: 'B', description: 'db', dependsOn: [0], estimatedHours: 3 },
        ],
      },
    });

    const res = await breakdownTaskFlow({
      repoId: 'x_y',
      goal: 'spec',
      requestedBy: 'u1',
    });

    expect(res.subtasks).toHaveLength(2);
    expect(mockParse).toHaveBeenCalledTimes(1);

    const docA = store.get('apps/gitsync/repos/x_y/tasks/t0');
    const docB = store.get('apps/gitsync/repos/x_y/tasks/t1');
    expect(docA).toMatchObject({
      title: 'A',
      status: 'todo',
      source: 'ai_breakdown',
      createdBy: 'u1',
      parentTaskId: null,
      dependsOn: [],
      estimatedHours: 2,
    });
    expect(docA?.createdAt).toBe('__serverTimestamp__');
    expect(docB).toMatchObject({ title: 'B', source: 'ai_breakdown' });
  });

  it('prepends readRepoPlanningDocs content to the OpenAI context and drops the "newly imported" line', async () => {
    seedRepo('x_y', { name: 'x/y', description: 'a demo' });
    repoDocsResult = {
      content: '## Project progress (.trellis)\n\n3 tasks — done 2 / in_progress 1 / todo 0',
      summary: '2/3 tasks done; 1 open',
      source: 'trellis',
      cached: false,
    };
    parseQueue.push({ parsed: { subtasks: [] } });

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    expect(mockReadRepoPlanningDocs).toHaveBeenCalledWith('x_y');
    const userMsg = firstUserMessage();
    expect(userMsg).toContain('## Project progress (.trellis)');
    expect(userMsg).not.toContain('This is a newly imported project');
  });

  it('keeps the "newly imported" line when no planning docs are found', async () => {
    seedRepo('x_y', { name: 'x/y' });
    // repoDocsResult defaults to the empty none result.
    parseQueue.push({ parsed: { subtasks: [] } });

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    expect(firstUserMessage()).toContain('This is a newly imported project');
  });

  it('prepends the project brief at the top of the context when one exists (W3a)', async () => {
    seedRepo('x_y', { name: 'x/y' });
    store.set('apps/gitsync/repos/x_y/meta/projectBrief', {
      content: '- uses OpenAI SDK, not Genkit',
      updatedAt: '__serverTimestamp__',
      version: 3,
    });
    parseQueue.push({ parsed: { subtasks: [] } });

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    const userMsg = firstUserMessage();
    // Brief block sits at the very top of projectContext (stable cache prefix).
    expect(userMsg).toContain('## Project memory');
    expect(userMsg).toContain('- uses OpenAI SDK, not Genkit');
    expect(userMsg.indexOf('## Project memory')).toBeLessThan(
      userMsg.indexOf('Repository: x/y'),
    );
  });

  it('leaves the context unchanged when no project brief exists (W3a)', async () => {
    seedRepo('x_y', { name: 'x/y' });
    parseQueue.push({ parsed: { subtasks: [] } });

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    expect(firstUserMessage()).not.toContain('Project memory');
  });

  it('translates dependsOn 0-based indices into real taskIds', async () => {
    seedRepo('x_y', { name: 'x/y' });
    parseQueue.push({
      parsed: {
        subtasks: [
          { title: 'A', description: '', dependsOn: [], estimatedHours: 1 },
          { title: 'B', description: '', dependsOn: [0], estimatedHours: 1 },
          { title: 'C', description: '', dependsOn: [0, 1], estimatedHours: 1 },
        ],
      },
    });

    const res = await breakdownTaskFlow({
      repoId: 'x_y',
      goal: 'spec',
      requestedBy: 'u1',
    });

    const idA = res.subtasks[0].id;
    const idB = res.subtasks[1].id;
    expect(res.subtasks[1].dependsOn).toEqual([idA]);
    expect(res.subtasks[2].dependsOn).toEqual([idA, idB]);

    // Persisted docs carry the translated string ids, not the indices.
    const docC = store.get(`apps/gitsync/repos/x_y/tasks/${res.subtasks[2].id}`);
    expect(docC?.dependsOn).toEqual([idA, idB]);
  });

  it('drops out-of-range dependsOn indices', async () => {
    seedRepo('x_y', { name: 'x/y' });
    parseQueue.push({
      parsed: {
        subtasks: [
          { title: 'A', description: '', dependsOn: [9, -1], estimatedHours: 1 },
        ],
      },
    });
    const res = await breakdownTaskFlow({
      repoId: 'x_y',
      goal: 'spec',
      requestedBy: 'u1',
    });
    expect(res.subtasks[0].dependsOn).toEqual([]);
  });

  it('re-prompts once on a cycle, succeeds when the retry is acyclic', async () => {
    seedRepo('x_y', { name: 'x/y' });
    // First parse: cyclic (0<->1). Second parse: acyclic.
    parseQueue.push({
      parsed: {
        subtasks: [
          { title: 'A', description: '', dependsOn: [1], estimatedHours: 1 },
          { title: 'B', description: '', dependsOn: [0], estimatedHours: 1 },
        ],
      },
    });
    parseQueue.push({
      parsed: {
        subtasks: [
          { title: 'A', description: '', dependsOn: [], estimatedHours: 1 },
          { title: 'B', description: '', dependsOn: [0], estimatedHours: 1 },
        ],
      },
    });

    const res = await breakdownTaskFlow({
      repoId: 'x_y',
      goal: 'spec',
      requestedBy: 'u1',
    });

    expect(mockParse).toHaveBeenCalledTimes(2);
    expect(res.subtasks).toHaveLength(2);
    expect(res.subtasks[0].dependsOn).toEqual([]);
    expect(res.subtasks[1].dependsOn).toEqual([res.subtasks[0].id]);
  });

  it('throws internal when the model is cyclic twice', async () => {
    seedRepo('x_y', { name: 'x/y' });
    const cyclic = {
      parsed: {
        subtasks: [
          { title: 'A', description: '', dependsOn: [1], estimatedHours: 1 },
          { title: 'B', description: '', dependsOn: [0], estimatedHours: 1 },
        ],
      },
    };
    parseQueue.push(cyclic);
    parseQueue.push(cyclic);

    await expect(
      breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' }),
    ).rejects.toMatchObject({ code: 'internal' });
    expect(mockParse).toHaveBeenCalledTimes(2);
  });

  it('takes the single-shot (parse) path only when the repo has NO tasks', async () => {
    seedRepo('x_y', { name: 'x/y' });
    parseQueue.push({ parsed: { subtasks: [] } });

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    // Empty repo → parse() used, the agentic create() never touched.
    expect(mockParse).toHaveBeenCalledTimes(1);
    expect(mockCreate).not.toHaveBeenCalled();
  });
});

// ---- hasCycleById (combined existing+new graph) ----------------------------

describe('hasCycleById', () => {
  it('returns false for an acyclic id graph', () => {
    expect(
      hasCycleById(
        new Map([
          ['a', []],
          ['b', ['a']],
          ['c', ['a', 'b']],
        ]),
      ),
    ).toBe(false);
  });

  it('detects a cycle that spans existing + new ids', () => {
    // existing 'e' depends on new 'n'; new 'n' depends back on 'e' → cycle.
    expect(
      hasCycleById(
        new Map([
          ['e', ['n']],
          ['n', ['e']],
        ]),
      ),
    ).toBe(true);
  });

  it('ignores edges that point at unknown ids', () => {
    expect(hasCycleById(new Map([['a', ['ghost']]]))).toBe(false);
  });
});

// ---- breakdownTools repo isolation + pagination ----------------------------

describe('breakdownTools repo isolation', () => {
  it('listExistingTaskTitles reads ONLY the requested repo', async () => {
    seedTask('repo_a', 'a1', { title: 'A one' });
    seedTask('repo_a', 'a2', { title: 'A two' });
    seedTask('repo_b', 'b1', { title: 'B one' }); // different repo

    const page = await listExistingTaskTitles('repo_a');
    const ids = page.tasks.map((t) => t.taskId).sort();
    expect(ids).toEqual(['a1', 'a2']);
    expect(page.tasks.some((t) => t.taskId === 'b1')).toBe(false);
  });

  it('searchExistingTasks reads ONLY the requested repo', async () => {
    seedTask('repo_a', 'a1', { title: 'add auth login', dependsOn: ['x'] });
    seedTask('repo_b', 'b1', { title: 'add auth login' }); // same words, other repo

    const res = await searchExistingTasks('repo_a', 'auth');
    expect(res.map((t) => t.taskId)).toEqual(['a1']);
    expect(res[0].dependsOn).toEqual(['x']);
  });

  it('listExistingTaskTitles paginates with a cursor (does not dump all)', async () => {
    // 26 tasks → first page is capped at 25 with a nextCursor.
    for (let i = 0; i < 26; i++) {
      const id = `t${String(i).padStart(2, '0')}`;
      seedTask('repo_a', id, { title: `task ${i}` });
    }
    const first = await listExistingTaskTitles('repo_a');
    expect(first.tasks).toHaveLength(25);
    expect(first.nextCursor).toBe('t24');

    const second = await listExistingTaskTitles('repo_a', { cursor: first.nextCursor! });
    expect(second.tasks).toHaveLength(1);
    expect(second.tasks[0].taskId).toBe('t25');
    expect(second.nextCursor).toBeNull();
  });

  it('listExistingTaskTitles logs a success page count (prd 06-15)', async () => {
    seedTask('repo_a', 'a1', { title: 'A one' });
    seedTask('repo_a', 'a2', { title: 'A two' });

    await listExistingTaskTitles('repo_a');

    expect(infoLogs('listExistingTaskTitles: page')[0]).toMatchObject({
      repoId: 'repo_a',
      count: 2,
      hasMore: false,
    });
  });

  it('searchExistingTasks logs a success result count (prd 06-15)', async () => {
    seedTask('repo_a', 'a1', { title: 'add auth login' });

    await searchExistingTasks('repo_a', 'auth');

    expect(infoLogs('searchExistingTasks: results')[0]).toMatchObject({
      repoId: 'repo_a',
      query: 'auth',
      count: 1,
    });
  });
});

// ---- INCREMENTAL agentic path (repo already has tasks) ---------------------

describe('breakdownTaskFlow incremental path', () => {
  function seedNonEmptyRepo() {
    seedRepo('x_y', { name: 'x/y', description: 'a demo' });
    seedTask('x_y', 'existing1', { title: 'Set up auth', dependsOn: [] });
    seedTask('x_y', 'existing2', { title: 'Build profile page', dependsOn: ['existing1'] });
  }

  it('runs the agentic loop (not parse) and uses tools, never dumping all tasks', async () => {
    seedNonEmptyRepo();
    // Round 0: explore. Round 1: submit one new subtask depending on existing1.
    createQueue.push(readToolTurn('listExistingTaskTitles', {}));
    createQueue.push(
      submitTurn([
        {
          title: 'Add password reset',
          description: 'reset flow',
          estimatedHours: 4,
          dependsOnNew: [],
          dependsOnExisting: ['existing1'],
        },
      ]),
    );

    const res = await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    // Agentic path: create() used, parse() never.
    expect(mockCreate).toHaveBeenCalledTimes(2);
    expect(mockParse).not.toHaveBeenCalled();
    expect(res.subtasks).toHaveLength(1);

    // Context bounded: no message embeds the full existing-task title list.
    const text = JSON.stringify(allCreateMessages());
    // The flow's own messages never contain the existing titles — those only
    // reach the model via the tool-result we DIDN'T script into messages here.
    const flowAuthored = allCreateMessages().filter(
      (m) => m.role === 'system' || m.role === 'user',
    );
    const flowText = JSON.stringify(flowAuthored);
    expect(flowText).not.toContain('Set up auth');
    expect(flowText).not.toContain('Build profile page');
    // sanity: the loop genuinely invoked a tool call this run.
    expect(text).toContain('listExistingTaskTitles');
  });

  it('resolves dependsOnExisting to real taskIds and dependsOnNew to new ids', async () => {
    seedNonEmptyRepo();
    createQueue.push(
      submitTurn([
        {
          title: 'New A',
          description: '',
          estimatedHours: 1,
          dependsOnNew: [],
          dependsOnExisting: ['existing1'],
        },
        {
          title: 'New B',
          description: '',
          estimatedHours: 1,
          dependsOnNew: [0],
          dependsOnExisting: ['existing2'],
        },
      ]),
    );

    const res = await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    const idA = res.subtasks[0].id;
    expect(res.subtasks[0].dependsOn).toEqual(['existing1']);
    expect(res.subtasks[1].dependsOn).toEqual([idA, 'existing2']);

    // Persisted docs carry the resolved string ids.
    const docB = store.get(`apps/gitsync/repos/x_y/tasks/${res.subtasks[1].id}`);
    expect(docB).toMatchObject({ source: 'ai_breakdown', status: 'todo' });
    expect(docB?.dependsOn).toEqual([idA, 'existing2']);
  });

  it('drops unknown dependsOnExisting ids', async () => {
    seedNonEmptyRepo();
    createQueue.push(
      submitTurn([
        {
          title: 'New A',
          description: '',
          estimatedHours: 1,
          dependsOnNew: [],
          dependsOnExisting: ['existing1', 'does_not_exist'],
        },
      ]),
    );

    const res = await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });
    expect(res.subtasks[0].dependsOn).toEqual(['existing1']);
  });

  it('re-prompts once on a combined existing+new cycle, succeeds when fixed', async () => {
    seedRepo('x_y', { name: 'x/y' });
    seedTask('x_y', 'e1', { title: 'E1', dependsOn: ['e2'] });
    seedTask('x_y', 'e2', { title: 'E2', dependsOn: [] });

    // First submit: two new tasks reference each other both ways (a cycle once
    // combined with the existing graph). Second submit (after feedback): acyclic.
    createQueue.push(
      submitTurn([
        { title: 'N0', description: '', estimatedHours: 1, dependsOnNew: [1], dependsOnExisting: [] },
        { title: 'N1', description: '', estimatedHours: 1, dependsOnNew: [0], dependsOnExisting: [] },
      ]),
    );
    // Second submit (after cycle feedback): acyclic.
    createQueue.push(
      submitTurn([
        { title: 'N0', description: '', estimatedHours: 1, dependsOnNew: [], dependsOnExisting: ['e1'] },
        { title: 'N1', description: '', estimatedHours: 1, dependsOnNew: [0], dependsOnExisting: [] },
      ]),
    );

    const res = await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    expect(mockCreate).toHaveBeenCalledTimes(2);
    expect(res.subtasks).toHaveLength(2);
    expect(res.subtasks[0].dependsOn).toEqual(['e1']);
    expect(res.subtasks[1].dependsOn).toEqual([res.subtasks[0].id]);
  });

  it('throws when the combined graph is cyclic twice (nothing written)', async () => {
    seedNonEmptyRepo();
    const cyclic = submitTurn([
      { title: 'N0', description: '', estimatedHours: 1, dependsOnNew: [1], dependsOnExisting: [] },
      { title: 'N1', description: '', estimatedHours: 1, dependsOnNew: [0], dependsOnExisting: [] },
    ]);
    createQueue.push(cyclic);
    createQueue.push(submitTurn([
      { title: 'N0', description: '', estimatedHours: 1, dependsOnNew: [1], dependsOnExisting: [] },
      { title: 'N1', description: '', estimatedHours: 1, dependsOnNew: [0], dependsOnExisting: [] },
    ]));

    await expect(
      breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' }),
    ).rejects.toMatchObject({ code: 'internal' });
    // No new task docs were written (only the 2 seeded existing ones remain).
    expect(batchWrites).toHaveLength(0);
  });

  it('answers sibling read tool_calls when a turn batches a read + submit (no dangling tool_call)', async () => {
    seedNonEmptyRepo();
    // Round 0: one assistant turn with BOTH a read tool AND a malformed submit
    // (missing required fields → schema fails → loop must `continue`). If the
    // sibling read tool_call is left unanswered, the real OpenAI API would 400
    // on the next request.
    createQueue.push(
      readPlusSubmitTurn(
        { name: 'listExistingTaskTitles', args: {}, id: 'read-0' },
        [{ title: 'bad' /* missing description/estimatedHours */ }],
        'sub-bad',
      ),
    );
    // Round 1: a clean submit ends the loop.
    createQueue.push(
      submitTurn(
        [
          {
            title: 'Add password reset',
            description: 'reset flow',
            estimatedHours: 4,
            dependsOnNew: [],
            dependsOnExisting: ['existing1'],
          },
        ],
        'sub-final',
      ),
    );

    const res = await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    expect(res.subtasks).toHaveLength(1);
    expect(mockCreate).toHaveBeenCalledTimes(2);
    // The batched read tool_call AND the malformed-submit tool_call both got a
    // role:'tool' reply before round 1's request.
    assertNoDanglingToolCalls();
    const toolReplies = allCreateMessages().filter((m) => m.role === 'tool');
    const repliedIds = toolReplies.map(
      (m) => (m as unknown as { tool_call_id: string }).tool_call_id,
    );
    expect(repliedIds).toContain('read-0');
    expect(repliedIds).toContain('sub-bad');
  });

  it('throws when the loop ends without submitBreakdown (nothing written)', async () => {
    seedNonEmptyRepo();
    // 5 rounds of only read tools, never submit.
    for (let i = 0; i < 5; i++) {
      createQueue.push(readToolTurn('listExistingTaskTitles', {}, `tc${i}`));
    }

    await expect(
      breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' }),
    ).rejects.toMatchObject({ code: 'internal' });
    expect(mockCreate).toHaveBeenCalledTimes(5);
    expect(batchWrites).toHaveLength(0);
  });

  it('logs each read tool call with a resultCount (observability, prd 06-15)', async () => {
    seedNonEmptyRepo();
    // Round 0: list existing tasks. Round 1: search. Round 2: submit.
    createQueue.push(readToolTurn('listExistingTaskTitles', {}, 'tc-list'));
    createQueue.push(
      readToolTurn('searchExistingTasks', { query: 'auth', limit: 5 }, 'tc-search'),
    );
    createQueue.push(
      submitTurn([
        {
          title: 'Add password reset',
          description: 'reset flow',
          estimatedHours: 4,
          dependsOnNew: [],
          dependsOnExisting: ['existing1'],
        },
      ]),
    );

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    const toolLogs = infoLogs('incrementalBreakdown: tool call');
    const listLog = toolLogs.find((l) => l.tool === 'listExistingTaskTitles');
    expect(listLog).toMatchObject({
      repoId: 'x_y',
      round: 0,
      tool: 'listExistingTaskTitles',
    });
    // Two seeded existing tasks → page length 2.
    expect(listLog?.resultCount).toBe(2);

    const searchLog = toolLogs.find((l) => l.tool === 'searchExistingTasks');
    expect(searchLog).toMatchObject({
      repoId: 'x_y',
      round: 1,
      tool: 'searchExistingTasks',
      args: { query: 'auth', limit: 5 },
    });
    expect(typeof searchLog?.resultCount).toBe('number');
  });

  it('logs submit with totalDependsOnExisting (observability, prd 06-15)', async () => {
    seedNonEmptyRepo();
    createQueue.push(
      submitTurn([
        {
          title: 'New A',
          description: '',
          estimatedHours: 1,
          dependsOnNew: [],
          dependsOnExisting: ['existing1'],
        },
        {
          title: 'New B',
          description: '',
          estimatedHours: 1,
          dependsOnNew: [0],
          dependsOnExisting: ['existing2'],
        },
      ]),
    );

    await breakdownTaskFlow({ repoId: 'x_y', goal: 'spec', requestedBy: 'u1' });

    const submitLogs = infoLogs('incrementalBreakdown: submit');
    expect(submitLogs).toHaveLength(1);
    expect(submitLogs[0]).toMatchObject({
      repoId: 'x_y',
      subtaskCount: 2,
      totalDependsOnNew: 1,
      totalDependsOnExisting: 2,
    });
  });

  it('threads `language` into the incremental system prompt (W6)', async () => {
    seedNonEmptyRepo();
    createQueue.push(
      submitTurn([
        {
          title: 'Add password reset',
          description: 'reset flow',
          estimatedHours: 4,
          dependsOnNew: [],
          dependsOnExisting: ['existing1'],
        },
      ]),
    );

    await breakdownTaskFlow({
      repoId: 'x_y',
      goal: 'spec',
      requestedBy: 'u1',
      language: 'Traditional Chinese',
    });

    const system = allCreateMessages().find((m) => m.role === 'system');
    expect(String(system?.content)).toContain(
      'Write your entire response in Traditional Chinese.',
    );
    // Still routed through the shared base (buildSystemPrompt prefix).
    expect(String(system?.content)).toContain(GITSYNC_BASE_SYSTEM);
  });
});

// ---- incrementalBreakdownSystem prompt (buildSystemPrompt + W6 language) ----

describe('incrementalBreakdownSystem', () => {
  it('routes through buildSystemPrompt (carries the shared GITSYNC_BASE_SYSTEM prefix)', () => {
    const prompt = incrementalBreakdownSystem();
    expect(prompt.startsWith(GITSYNC_BASE_SYSTEM)).toBe(true);
  });

  it('keeps the incremental-specific semantics in the agent body', () => {
    const prompt = incrementalBreakdownSystem();
    // No dump — explore via tools.
    expect(prompt).toContain('do NOT dump the task list');
    expect(prompt).toContain('listExistingTaskTitles');
    // Real taskIds, never invented.
    expect(prompt).toContain('never invent ids');
    // dependsOn two columns + DAG + terminator + shallow.
    expect(prompt).toContain('dependsOnNew');
    expect(prompt).toContain('dependsOnExisting');
    expect(prompt).toContain('MUST be acyclic');
    expect(prompt).toContain('SHALLOW');
    expect(prompt).toContain('submitBreakdown');
  });

  it('appends the language directive only when `language` is given (cache-friendly)', () => {
    const base = incrementalBreakdownSystem();
    expect(base).not.toContain('Write your entire response in');

    const zh = incrementalBreakdownSystem('Traditional Chinese');
    expect(zh).toContain('Write your entire response in Traditional Chinese.');
    // The language run is exactly the base plus the one trailing directive line.
    expect(zh).toBe(`${base}\n\n---\n\nWrite your entire response in Traditional Chinese.`);
  });

  it('treats empty/whitespace language as no directive', () => {
    expect(incrementalBreakdownSystem('   ')).toBe(incrementalBreakdownSystem());
  });
});
