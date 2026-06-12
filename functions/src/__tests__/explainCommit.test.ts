// Unit tests for explainCommitFlow (tap-a-commit AI work summary).
//
// Same boundary-mock style as summarizeDay.test.ts: fake Firestore (equality
// clauses honored), scripted OpenAI, no-op logger.

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

// Honors '==' (incl. dotted paths like author.login); ignores ranges/order.
function getField(d: Record<string, unknown>, field: string): unknown {
  return field.split('.').reduce<unknown>((acc, k) => {
    if (acc && typeof acc === 'object') return (acc as Record<string, unknown>)[k];
    return undefined;
  }, d);
}

function makeQuery(colPath: string, clauses: Array<{ field: string; op: string; value: unknown }>) {
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

let nextContent: string | null = '**What was done** — wired OAuth.';
const mockCreate = jest.fn(async () => ({
  choices: [{ message: { role: 'assistant', content: nextContent } }],
}));

jest.mock('../config', () => ({
  getOpenAI: () => ({ chat: { completions: { create: mockCreate } } }),
  MODELS: { reasoning: 'gpt-4o', fast: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
}));

const mockGetCommit = jest.fn();
jest.mock('../services/githubClient', () => ({
  getCommit: (...args: unknown[]) => mockGetCommit(...args),
}));

import { explainCommitFlow } from '../flows/explainCommit';

const REPO = 'team17_gitsync';

function seedCommit(sha: string, data: Record<string, unknown>) {
  store.set(`apps/gitsync/repos/${REPO}/commits/${sha}`, {
    message: 'Wire up GitHub OAuth provider',
    author: { login: 'alice-dev', name: 'Alice' },
    filesChanged: ['lib/services/authentication.dart'],
    additions: 45,
    deletions: 3,
    ...data,
  });
}

beforeEach(() => {
  store.clear();
  updateSpy.mockClear();
  mockCreate.mockClear();
  mockGetCommit.mockReset();
  nextContent = '**What was done** — wired OAuth.';
});

describe('explainCommitFlow', () => {
  it('throws not-found for a missing commit (no GitHub fallback creds)', async () => {
    await expect(
      explainCommitFlow({ repoId: REPO, sha: 'nope' }),
    ).rejects.toMatchObject({ code: 'not-found' });
    expect(mockCreate).not.toHaveBeenCalled();
    expect(mockGetCommit).not.toHaveBeenCalled();
  });

  it('falls back to the GitHub API when the doc is missing (06-05 D2)', async () => {
    mockGetCommit.mockResolvedValue({
      sha: 'branch1',
      message: 'feat: branch-only work',
      authorLogin: 'bob-dev',
      authorName: 'Bob',
      committedAt: '2026-06-05T00:00:00Z',
      files: ['lib/views/commits/branch_view.dart'],
      additions: 80,
      deletions: 10,
    });

    const res = await explainCommitFlow({
      repoId: REPO,
      sha: 'branch1',
      owner: 'team17',
      repo: 'gitsync',
      accessToken: 'tok',
    });

    expect(res.cached).toBe(false);
    expect(res.markdown).toContain('What was done');
    expect(mockGetCommit).toHaveBeenCalledWith('team17', 'gitsync', 'tok', 'branch1');
    expect(mockCreate).toHaveBeenCalledTimes(1);
    // No cache write on the fallback path (no doc to cache on).
    expect(updateSpy).not.toHaveBeenCalled();
    // The prompt context was built from the GitHub commit message.
    const userMsg = (mockCreate.mock.calls[0] as unknown as [
      { messages: Array<{ role: string; content: string }> },
    ])[0].messages.find((m) => m.role === 'user');
    expect(userMsg?.content).toContain('branch-only work');
  });

  it('still throws not-found when the doc is missing and no token is supplied', async () => {
    await expect(
      explainCommitFlow({
        repoId: REPO,
        sha: 'branch1',
        owner: 'team17',
        repo: 'gitsync',
        // accessToken intentionally absent
      }),
    ).rejects.toMatchObject({ code: 'not-found' });
    expect(mockGetCommit).not.toHaveBeenCalled();
    expect(mockCreate).not.toHaveBeenCalled();
  });

  it('returns the cached workSummary without calling OpenAI', async () => {
    seedCommit('c1', { workSummary: 'cached explanation' });

    const res = await explainCommitFlow({ repoId: REPO, sha: 'c1' });

    expect(res).toEqual({ markdown: 'cached explanation', cached: true });
    expect(mockCreate).not.toHaveBeenCalled();
    expect(updateSpy).not.toHaveBeenCalled();
  });

  it('generates, returns, and caches a summary on first tap', async () => {
    seedCommit('c1', { linkedTaskIds: ['t1'] });
    store.set(`apps/gitsync/repos/${REPO}/tasks/t1`, {
      title: 'OAuth sign-in',
      status: 'done',
    });
    // A neighboring commit by the same author for narrative context.
    seedCommit('c0', { message: 'Add auth scaffolding' });

    const res = await explainCommitFlow({ repoId: REPO, sha: 'c1' });

    expect(res.cached).toBe(false);
    expect(res.markdown).toContain('What was done');
    expect(mockCreate).toHaveBeenCalledTimes(1);
    // Cache written back onto the commit doc.
    expect(updateSpy).toHaveBeenCalledWith(
      `apps/gitsync/repos/${REPO}/commits/c1`,
      expect.objectContaining({
        workSummary: res.markdown,
        workSummaryGeneratedAt: '__ts__',
      }),
    );
    // The prompt grounding included the linked task and the neighbor commit.
    const userMsg = (mockCreate.mock.calls[0] as unknown as [
      { messages: Array<{ role: string; content: string }> },
    ])[0].messages.find((m) => m.role === 'user');
    expect(userMsg?.content).toContain('OAuth sign-in');
    expect(userMsg?.content).toContain('Add auth scaffolding');
  });

  it('force=true regenerates even when a cache exists', async () => {
    seedCommit('c1', { workSummary: 'stale' });
    nextContent = 'fresh explanation';

    const res = await explainCommitFlow({ repoId: REPO, sha: 'c1', force: true });

    expect(res).toEqual({ markdown: 'fresh explanation', cached: false });
    expect(mockCreate).toHaveBeenCalledTimes(1);
  });

  it('throws internal when OpenAI returns nothing', async () => {
    seedCommit('c1', {});
    nextContent = null;

    await expect(
      explainCommitFlow({ repoId: REPO, sha: 'c1' }),
    ).rejects.toMatchObject({ code: 'internal' });
    expect(updateSpy).not.toHaveBeenCalled();
  });
});
