// Unit tests for generateHandoffFlow (AI handoff doc for a now-ready task).
//
// Same boundary-mock style as explainCommit.test.ts: fake Firestore (equality
// clauses honored; array-contains is treated as a pass-through so all seeded
// commits are returned), scripted OpenAI, mocked tool helpers, no-op logger.

class FakeHttpsError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'HttpsError';
  }
}

jest.mock('firebase-functions/v2/https', () => ({ HttpsError: FakeHttpsError }));
jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));
jest.mock('firebase-admin/firestore', () => ({
  FieldValue: { serverTimestamp: () => '__ts__' },
}));

const store = new Map<string, Record<string, unknown>>();
const updateSpy = jest.fn();

function childDocsOf(colPath: string): Array<[string, Record<string, unknown>]> {
  return [...store.entries()].filter(
    ([p]) =>
      p.startsWith(`${colPath}/`) &&
      p.slice(colPath.length + 1).indexOf('/') === -1,
  );
}

function getField(d: Record<string, unknown>, field: string): unknown {
  return field.split('.').reduce<unknown>((acc, k) => {
    if (acc && typeof acc === 'object') return (acc as Record<string, unknown>)[k];
    return undefined;
  }, d);
}

function makeQuery(
  colPath: string,
  clauses: Array<{ field: string; op: string; value: unknown }>,
) {
  const matches = () =>
    childDocsOf(colPath).filter(([, d]) =>
      clauses.every((c) => (c.op === '==' ? getField(d, c.field) === c.value : true)),
    );
  const q = {
    where(field: string, op: string, value: unknown) {
      return makeQuery(colPath, [...clauses, { field, op, value }]);
    },
    orderBy() {
      return q;
    },
    limit() {
      return q;
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
  return q;
}

const fakeDb = {
  doc: (path: string) => ({
    path,
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
    async update(patch: Record<string, unknown>) {
      store.set(path, { ...(store.get(path) ?? {}), ...patch });
      updateSpy(path, patch);
    },
  }),
  collection: (path: string) => makeQuery(path, []),
};

jest.mock('../admin', () => ({ db: fakeDb, REGION: 'asia-east1' }));

let nextContent: string | null = '## What was done\n- Shipped the API.';
const mockCreate = jest.fn(async () => ({
  choices: [{ message: { role: 'assistant', content: nextContent } }],
}));

jest.mock('../config', () => ({
  getOpenAI: () => ({ chat: { completions: { create: mockCreate } } }),
  MODELS: { reasoning: 'gpt-4o', fast: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
}));

jest.mock('../tools/discordSearch', () => ({
  searchDiscordMessages: jest.fn(async () => []),
}));
jest.mock('../tools/assignTools', () => ({
  readTeamState: jest.fn(async () => [
    {
      userId: 'u1',
      name: 'Alice',
      githubLogin: 'alice-dev',
      discordUserId: null,
      activeIssueCount: 0,
      expertiseTags: [],
      lastActiveAt: null,
    },
  ]),
}));

import { generateHandoffFlow } from '../flows/generateHandoff';

const REPO = 'team17_gitsync';

beforeEach(() => {
  store.clear();
  updateSpy.mockClear();
  mockCreate.mockClear();
  nextContent = '## What was done\n- Shipped the API.';
});

function seedTasks() {
  store.set(`apps/gitsync/repos/${REPO}/tasks/t-ui`, {
    title: 'Build the task UI',
    description: 'Render the detail page.',
    dependsOn: ['t-api'],
    acceptanceCriteria: ['Renders the list'],
  });
  store.set(`apps/gitsync/repos/${REPO}/tasks/t-api`, {
    title: 'Build the API endpoint',
    description: 'Add the callable.',
    status: 'done',
  });
  store.set(`apps/gitsync/repos/${REPO}/commits/c1`, {
    message: 'feat: add API endpoint\n\nbody text',
    linkedTaskIds: ['t-api'],
    author: { name: 'Bob', login: 'bob-dev' },
    filesChanged: ['functions/src/handlers/api.ts'],
    committedAt: '2026-06-06T00:00:00Z',
  });
}

describe('generateHandoffFlow', () => {
  it('throws not-found when the task is missing', async () => {
    await expect(
      generateHandoffFlow({ repoId: REPO, taskId: 'nope' }),
    ).rejects.toMatchObject({ code: 'not-found' });
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it('returns the cached handoffDoc without calling OpenAI (force=false)', async () => {
    store.set(`apps/gitsync/repos/${REPO}/tasks/t-ui`, {
      title: 'Build the task UI',
      handoffDoc: 'cached handoff',
    });

    const res = await generateHandoffFlow({ repoId: REPO, taskId: 't-ui' });

    expect(res).toEqual({ handoffMarkdown: 'cached handoff', cached: true });
    expect(mockCreate).not.toHaveBeenCalled();
    expect(updateSpy).not.toHaveBeenCalled();
  });

  it('generates from prerequisites + commits and writes the handoff back', async () => {
    seedTasks();

    const res = await generateHandoffFlow({ repoId: REPO, taskId: 't-ui' });

    expect(res.cached).toBe(false);
    expect(res.handoffMarkdown).toContain('What was done');
    expect(mockCreate).toHaveBeenCalledTimes(1);
    expect(updateSpy).toHaveBeenCalledWith(
      `apps/gitsync/repos/${REPO}/tasks/t-ui`,
      expect.objectContaining({
        handoffDoc: res.handoffMarkdown,
        handoffGeneratedAt: '__ts__',
      }),
    );
    // Grounding: the prompt carries the prerequisite title + the commit subject.
    const userMsg = (mockCreate.mock.calls[0] as unknown as [
      { messages: Array<{ role: string; content: string }> },
    ])[0].messages.find((m) => m.role === 'user');
    expect(userMsg?.content).toContain('Build the API endpoint');
    expect(userMsg?.content).toContain('add API endpoint');
    expect(userMsg?.content).toContain('Renders the list');
  });

  it('force=true regenerates even when a handoffDoc exists', async () => {
    seedTasks();
    store.set(`apps/gitsync/repos/${REPO}/tasks/t-ui`, {
      ...(store.get(`apps/gitsync/repos/${REPO}/tasks/t-ui`) ?? {}),
      handoffDoc: 'stale handoff',
    });
    nextContent = '## What was done\n- Fresh handoff.';

    const res = await generateHandoffFlow({
      repoId: REPO,
      taskId: 't-ui',
      force: true,
    });

    expect(res.cached).toBe(false);
    expect(res.handoffMarkdown).toContain('Fresh handoff');
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  it('throws internal when OpenAI returns nothing', async () => {
    seedTasks();
    nextContent = null;

    await expect(
      generateHandoffFlow({ repoId: REPO, taskId: 't-ui' }),
    ).rejects.toMatchObject({ code: 'internal' });
    expect(updateSpy).not.toHaveBeenCalled();
  });
});
