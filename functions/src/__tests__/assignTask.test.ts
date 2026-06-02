// Unit tests for assignTaskFlow.
//
// Boundary mocks (same style as breakdownTask.test.ts / onIssueWritten.test.ts):
//   - firebase-functions/v2/https → HttpsError captures `code`.
//   - firebase-functions/v2 → logger no-op.
//   - firebase-admin/firestore → FieldValue.serverTimestamp + increment sentinels.
//   - ../admin → hand-rolled fake Firestore (doc/collection/where/findNearest/runTransaction).
//   - ../config → getOpenAI returns a mock whose chat.completions.create() is scripted per-test.
//   - ../tools/embedding → embed() stubbed (no real OpenAI embedding call).

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
    serverTimestamp: () => '__ts__',
    increment: (n: number) => ({ __inc__: n }),
  },
}));

// ---- Fake Firestore -------------------------------------------------------

const store = new Map<string, Record<string, unknown>>();

// When set, the fake findNearest().get() throws this (simulates a missing
// vector index `9 FAILED_PRECONDITION` or any query failure).
let findNearestError: Error | null = null;

function childDocsOf(colPath: string): Array<[string, Record<string, unknown>]> {
  return [...store.entries()].filter(
    ([p]) =>
      p.startsWith(`${colPath}/`) &&
      p.slice(colPath.length + 1).indexOf('/') === -1,
  );
}

function applyPatch(path: string, patch: Record<string, unknown>) {
  const cur = { ...(store.get(path) ?? {}) };
  for (const [k, v] of Object.entries(patch)) {
    if (v && typeof v === 'object' && '__inc__' in (v as object)) {
      cur[k] = ((cur[k] as number) ?? 0) + (v as { __inc__: number }).__inc__;
    } else {
      cur[k] = v;
    }
  }
  store.set(path, cur);
}

// Resolve a possibly-nested field path ("author.login") on a doc.
function getField(data: Record<string, unknown>, field: string): unknown {
  return field.split('.').reduce<unknown>((acc, k) => {
    if (acc && typeof acc === 'object') return (acc as Record<string, unknown>)[k];
    return undefined;
  }, data);
}

interface WhereClause {
  field: string;
  op: string;
  value: unknown;
}

function makeQuery(colPath: string, clauses: WhereClause[]) {
  const matches = () =>
    childDocsOf(colPath).filter(([, d]) =>
      clauses.every((c) => {
        const fv = getField(d, c.field);
        if (c.op === 'array-contains') {
          return Array.isArray(fv) && (fv as unknown[]).includes(c.value);
        }
        return fv === c.value;
      }),
    );
  return {
    where(field: string, op: string, value: unknown) {
      return makeQuery(colPath, [...clauses, { field, op, value }]);
    },
    findNearest(_opts: unknown) {
      return {
        async get() {
          if (findNearestError) throw findNearestError;
          return {
            docs: matches().map(([p, d]) => ({
              id: p.split('/').pop() as string,
              data: () => d,
            })),
          };
        },
      };
    },
    async get() {
      return {
        docs: matches().map(([p, d]) => ({
          id: p.split('/').pop() as string,
          data: () => d,
        })),
      };
    },
  };
}

const fakeDb = {
  doc: (path: string) => ({
    path,
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
  }),
  collection: (path: string) => makeQuery(path, []),
  async runTransaction(fn: (tx: unknown) => Promise<unknown>) {
    const tx = {
      async get(ref: { path: string }) {
        const data = store.get(ref.path);
        return { exists: data !== undefined, data: () => data };
      },
      update(ref: { path: string }, patch: Record<string, unknown>) {
        applyPatch(ref.path, patch);
      },
    };
    return fn(tx);
  },
};

jest.mock('../admin', () => ({ db: fakeDb, REGION: 'asia-east1' }));

// ---- Fake OpenAI + embed --------------------------------------------------

const createQueue: Array<{ message: unknown }> = [];
const mockCreate = jest.fn(async () => {
  const next = createQueue.shift();
  if (!next) throw new Error('createQueue empty — test under-scripted OpenAI');
  return { choices: [next] };
});

jest.mock('../config', () => ({
  getOpenAI: () => ({ chat: { completions: { create: mockCreate } } }),
  MODELS: { reasoning: 'gpt-4o', fast: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
}));

jest.mock('../tools/embedding', () => ({
  embed: jest.fn(async () => new Array(1536).fill(0)),
}));

import { assignTaskFlow } from '../flows/assignTask';
import { searchMemberCommits } from '../tools/assignTools';

// ---- Helpers --------------------------------------------------------------

const REPO = 'octocat_hello';

function seedTask(taskId: string, data: Record<string, unknown>) {
  store.set(`apps/gitsync/repos/${REPO}/tasks/${taskId}`, {
    title: 't',
    status: 'todo',
    ...data,
  });
}

function seedMember(userId: string, member: Record<string, unknown>, user?: Record<string, unknown>) {
  store.set(`apps/gitsync/repos/${REPO}/members/${userId}`, {
    activeIssueCount: 0,
    ...member,
  });
  if (user) store.set(`apps/gitsync/users/${userId}`, user);
}

// Script an assistant turn that calls finalizeAssignment.
function finalizeTurn(assigneeId: string, reason: string, id = 'tc1') {
  return {
    message: {
      role: 'assistant',
      content: null,
      tool_calls: [
        {
          id,
          type: 'function',
          function: {
            name: 'finalizeAssignment',
            arguments: JSON.stringify({ assigneeId, reason }),
          },
        },
      ],
    },
  };
}

// Script an assistant turn that calls a read tool.
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

beforeEach(() => {
  store.clear();
  createQueue.length = 0;
  mockCreate.mockClear();
  findNearestError = null;
});

// ---- Tests ----------------------------------------------------------------

describe('assignTaskFlow pre-checks', () => {
  it('throws not-found when the task is missing', async () => {
    seedMember('u1', {}, { name: 'A' });
    await expect(
      assignTaskFlow({ repoId: REPO, taskId: 'missing' }),
    ).rejects.toMatchObject({ code: 'not-found' });
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it('throws failed-precondition when the task is already done', async () => {
    seedTask('t1', { status: 'done' });
    seedMember('u1', {}, { name: 'A' });
    await expect(
      assignTaskFlow({ repoId: REPO, taskId: 't1' }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it('throws failed-precondition when there are no members', async () => {
    seedTask('t1', {});
    await expect(
      assignTaskFlow({ repoId: REPO, taskId: 't1' }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(mockCreate).not.toHaveBeenCalled();
  });
});

describe('assignTaskFlow single-member shortcut', () => {
  it('assigns the only member without calling OpenAI', async () => {
    seedTask('t1', {});
    seedMember('u1', { activeIssueCount: 2 }, { name: 'Solo' });

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(res.assigneeId).toBe('u1');
    expect(mockCreate).not.toHaveBeenCalled();
    expect(store.get(`apps/gitsync/repos/${REPO}/tasks/t1`)?.assigneeId).toBe('u1');
    // counter bumped +1
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u1`)?.activeIssueCount).toBe(3);
  });
});

describe('assignTaskFlow agentic loop', () => {
  it('runs a read tool then finalizes, writing assignee + counter', async () => {
    seedTask('t1', {});
    seedMember('u1', { activeIssueCount: 1 }, { name: 'A', githubLogin: 'a' });
    seedMember('u2', { activeIssueCount: 0 }, { name: 'B', githubLogin: 'b' });

    // Round 0: model calls readTeamState. Round 1: model finalizes u2.
    createQueue.push(readToolTurn('readTeamState', {}));
    createQueue.push(finalizeTurn('u2', 'B has the lighter load.'));

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(res).toEqual({ assigneeId: 'u2', reasoning: 'B has the lighter load.' });
    expect(mockCreate).toHaveBeenCalledTimes(2);
    expect(store.get(`apps/gitsync/repos/${REPO}/tasks/t1`)?.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u2`)?.activeIssueCount).toBe(1);
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u1`)?.activeIssueCount).toBe(1);
  });

  it('rejects a finalize for a non-member and lets the model retry', async () => {
    seedTask('t1', {});
    seedMember('u1', {}, { name: 'A' });
    seedMember('u2', {}, { name: 'B' });

    createQueue.push(finalizeTurn('ghost', 'nope', 'bad'));
    createQueue.push(finalizeTurn('u1', 'A it is.', 'good'));

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(res.assigneeId).toBe('u1');
    expect(mockCreate).toHaveBeenCalledTimes(2);
  });

  it('reassign: old assignee -1, new assignee +1', async () => {
    seedTask('t1', { assigneeId: 'u1' });
    seedMember('u1', { activeIssueCount: 3 }, { name: 'A' });
    seedMember('u2', { activeIssueCount: 1 }, { name: 'B' });

    createQueue.push(finalizeTurn('u2', 'rebalancing to B.'));

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(res.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/tasks/t1`)?.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u1`)?.activeIssueCount).toBe(2);
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u2`)?.activeIssueCount).toBe(2);
  });
});

describe('assignTaskFlow fallback', () => {
  it('after 5 rounds without finalize, assigns the lowest activeIssueCount member', async () => {
    seedTask('t1', {});
    seedMember('u1', { activeIssueCount: 5 }, { name: 'A' });
    seedMember('u2', { activeIssueCount: 2 }, { name: 'B' }); // lowest
    seedMember('u3', { activeIssueCount: 9 }, { name: 'C' });

    // 5 rounds that only call a read tool, never finalize.
    for (let i = 0; i < 5; i++) {
      createQueue.push(readToolTurn('getTaskDependents', {}, `tc${i}`));
    }

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(mockCreate).toHaveBeenCalledTimes(5);
    expect(res.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/tasks/t1`)?.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u2`)?.activeIssueCount).toBe(3);
  });
});

describe('searchMemberCommits best-effort', () => {
  it('returns [] (does not throw) when findNearest fails with FAILED_PRECONDITION', async () => {
    seedMember('u1', {}, { name: 'A', githubLogin: 'a' });
    // Simulate the live failure: 9 FAILED_PRECONDITION: Missing vector index.
    findNearestError = new Error('9 FAILED_PRECONDITION: Missing vector index configuration');

    await expect(
      searchMemberCommits(REPO, 'u1', 'auth refactor'),
    ).resolves.toEqual([]);
  });

  it('still returns [] for a member without a githubLogin (existing early return)', async () => {
    seedMember('u1', {}, { name: 'A' }); // no githubLogin
    findNearestError = new Error('should never be reached');

    await expect(searchMemberCommits(REPO, 'u1', 'anything')).resolves.toEqual([]);
  });
});

describe('assignTaskFlow resilient to commit search failure', () => {
  it('finalizes via other signals even when searchMemberCommits throws', async () => {
    seedTask('t1', {});
    seedMember('u1', { activeIssueCount: 4 }, { name: 'A', githubLogin: 'a' });
    seedMember('u2', { activeIssueCount: 0 }, { name: 'B', githubLogin: 'b' }); // lighter

    // Missing commit vector index — every findNearest throws.
    findNearestError = new Error('9 FAILED_PRECONDITION: Missing vector index configuration');

    // Round 0: model probes commit history (search will degrade to []).
    // Round 1: model finalizes using workload signal.
    createQueue.push(readToolTurn('searchMemberCommits', { memberId: 'u2', query: 'topic' }));
    createQueue.push(finalizeTurn('u2', 'B has the lighter load; no commit signal available.'));

    const res = await assignTaskFlow({ repoId: REPO, taskId: 't1' });

    expect(res.assigneeId).toBe('u2');
    expect(mockCreate).toHaveBeenCalledTimes(2);
    expect(store.get(`apps/gitsync/repos/${REPO}/tasks/t1`)?.assigneeId).toBe('u2');
    expect(store.get(`apps/gitsync/repos/${REPO}/members/u2`)?.activeIssueCount).toBe(1);
  });
});
