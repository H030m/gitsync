// Unit tests for the triagePr flow (pure logic — summary + reviewers + tags).
//
// Boundary mocks:
//   - firebase-functions/v2 → logger no-op.
//   - ../services/githubClient → listPullRequestFiles + listCommitsForPath
//     return canned data per test.
//   - ../tools/assignTools → readTeamState returns a synthetic roster.
//   - ../config → getOpenAI with mocked chat.completions.create.

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

const mockListFiles = jest.fn();
const mockListCommitsForPath = jest.fn();
jest.mock('../services/githubClient', () => ({
  listPullRequestFiles: (...args: unknown[]) => mockListFiles(...args),
  listCommitsForPath: (...args: unknown[]) => mockListCommitsForPath(...args),
}));

const mockReadTeamState = jest.fn();
jest.mock('../tools/assignTools', () => ({
  readTeamState: (...args: unknown[]) => mockReadTeamState(...args),
}));

const mockChatCreate = jest.fn();
jest.mock('../config', () => ({
  getOpenAI: () => ({ chat: { completions: { create: mockChatCreate } } }),
  MODELS: { reasoning: 'gpt-4o', fast: 'gpt-4o-mini', embedding: 'text-embedding-3-small' },
  openaiKey: { value: () => 'k' },
}));

import { computeRiskTags, triagePr } from '../flows/triagePr';

const BASE_INPUT = {
  repoId: 'octocat_hello',
  prNumber: 42,
  prAuthorLogin: 'alice',
  title: 'Add login screen',
  body: 'Hooks up the login flow.',
  owner: 'octocat',
  repo: 'hello',
  accessToken: 'token',
};

function file(
  filename: string,
  additions = 10,
  deletions = 5,
  patch: string | null = '@@ -1 +1 @@\n-old\n+new',
) {
  return { filename, additions, deletions, status: 'modified', patch };
}

beforeEach(() => {
  mockListFiles.mockReset();
  mockListCommitsForPath.mockReset();
  mockReadTeamState.mockReset();
  mockChatCreate
    .mockReset()
    .mockResolvedValue({ choices: [{ message: { content: 'Summary line.' } }] });
});

describe('computeRiskTags', () => {
  it('flags large-diff above the 300 line threshold', () => {
    expect(computeRiskTags([file('a.ts', 200, 200)])).toContain('large-diff');
    expect(computeRiskTags([file('a.ts', 150, 100)])).not.toContain('large-diff');
  });

  it('flags touches-functions for any functions/ path', () => {
    expect(computeRiskTags([file('functions/src/x.ts', 1, 0)])).toContain(
      'touches-functions',
    );
    expect(computeRiskTags([file('lib/x.dart', 1, 0)])).not.toContain(
      'touches-functions',
    );
  });

  it('flags touches-rules for firestore.rules / firestore.indexes.json', () => {
    expect(computeRiskTags([file('firestore.rules', 1, 0)])).toContain(
      'touches-rules',
    );
    expect(
      computeRiskTags([file('firestore.indexes.json', 1, 0)]),
    ).toContain('touches-rules');
  });

  it('flags touches-schema for migrations/ or schema/ paths', () => {
    expect(computeRiskTags([file('db/migrations/001.sql', 1, 0)])).toContain(
      'touches-schema',
    );
    expect(computeRiskTags([file('schema/user.proto', 1, 0)])).toContain(
      'touches-schema',
    );
  });

  it('stacks multiple tags when all conditions hold', () => {
    const tags = computeRiskTags([
      file('functions/src/x.ts', 500, 0),
      file('firestore.rules', 1, 0),
    ]);
    expect(tags).toEqual(
      expect.arrayContaining(['large-diff', 'touches-functions', 'touches-rules']),
    );
  });
});

describe('triagePr', () => {
  it('returns top 2 reviewers, excludes PR author, ranks by file-history score', async () => {
    mockListFiles.mockResolvedValue([
      file('lib/login.dart', 100, 50),
      file('lib/auth.dart', 80, 20),
    ]);
    // bob appears recently in BOTH files → highest score
    // carol appears once, rank 0 in auth.dart
    // alice (PR author) must be excluded even if she appears
    mockListCommitsForPath.mockImplementation(
      async (_o: string, _r: string, _t: string, path: string) => {
        if (path === 'lib/login.dart') {
          return [
            { sha: 's1', authorLogin: 'bob', committedAt: '2026-06-01' },
            { sha: 's2', authorLogin: 'alice', committedAt: '2026-05-28' },
          ];
        }
        if (path === 'lib/auth.dart') {
          return [
            { sha: 's3', authorLogin: 'bob', committedAt: '2026-06-02' },
            { sha: 's4', authorLogin: 'carol', committedAt: '2026-05-25' },
            { sha: 's5', authorLogin: 'dave', committedAt: '2026-04-01' },
          ];
        }
        return [];
      },
    );
    mockReadTeamState.mockResolvedValue([
      { userId: 'uA', name: 'Alice', githubLogin: 'alice', discordUserId: '1', activeIssueCount: 0, expertiseTags: [], lastActiveAt: null },
      { userId: 'uB', name: 'Bob', githubLogin: 'bob', discordUserId: '2', activeIssueCount: 3, expertiseTags: [], lastActiveAt: null },
      { userId: 'uC', name: 'Carol', githubLogin: 'carol', discordUserId: '3', activeIssueCount: 1, expertiseTags: [], lastActiveAt: null },
      { userId: 'uD', name: 'Dave', githubLogin: 'dave', discordUserId: '4', activeIssueCount: 2, expertiseTags: [], lastActiveAt: null },
    ]);

    const result = await triagePr(BASE_INPUT);

    expect(result.summary).toBe('Summary line.');
    expect(result.recommendedReviewers.map((r) => r.userId)).toEqual(['uB', 'uC']);
    expect(result.recommendedReviewers[0]).toMatchObject({
      userId: 'uB',
      githubLogin: 'bob',
      discordUserId: '2',
    });
  });

  it('drops candidates whose githubLogin is not in the repo roster', async () => {
    mockListFiles.mockResolvedValue([file('a.ts')]);
    mockListCommitsForPath.mockResolvedValue([
      { sha: 's1', authorLogin: 'externalContributor', committedAt: '2026-06-01' },
      { sha: 's2', authorLogin: 'bob', committedAt: '2026-05-25' },
    ]);
    mockReadTeamState.mockResolvedValue([
      { userId: 'uB', name: 'Bob', githubLogin: 'bob', discordUserId: '2', activeIssueCount: 0, expertiseTags: [], lastActiveAt: null },
    ]);

    const result = await triagePr(BASE_INPUT);

    expect(result.recommendedReviewers.map((r) => r.userId)).toEqual(['uB']);
  });

  it('breaks score ties by lower activeIssueCount', async () => {
    // 2 files; bob appears as rank-0 sole committer in one, carol in the
    // other → identical scores (1 each). Tiebreak must prefer carol (lower load).
    mockListFiles.mockResolvedValue([file('a.ts'), file('b.ts')]);
    mockListCommitsForPath
      .mockResolvedValueOnce([{ sha: 's1', authorLogin: 'bob', committedAt: '2026-06-01' }])
      .mockResolvedValueOnce([{ sha: 's2', authorLogin: 'carol', committedAt: '2026-06-01' }]);
    mockReadTeamState.mockResolvedValue([
      { userId: 'uB', name: 'Bob', githubLogin: 'bob', discordUserId: '2', activeIssueCount: 5, expertiseTags: [], lastActiveAt: null },
      { userId: 'uC', name: 'Carol', githubLogin: 'carol', discordUserId: '3', activeIssueCount: 1, expertiseTags: [], lastActiveAt: null },
    ]);

    const result = await triagePr(BASE_INPUT);

    expect(result.recommendedReviewers.map((r) => r.userId)).toEqual(['uC', 'uB']);
  });

  it('listPullRequestFiles failure → empty result, never throws', async () => {
    mockListFiles.mockRejectedValue(new Error('boom'));
    const result = await triagePr(BASE_INPUT);
    expect(result).toEqual({
      summary: '',
      recommendedReviewers: [],
      riskTags: [],
    });
  });

  it('OpenAI failure → empty summary, but reviewers + tags still returned', async () => {
    mockListFiles.mockResolvedValue([file('functions/src/x.ts', 400, 0)]);
    mockListCommitsForPath.mockResolvedValue([
      { sha: 's1', authorLogin: 'bob', committedAt: '2026-06-01' },
    ]);
    mockReadTeamState.mockResolvedValue([
      { userId: 'uB', name: 'Bob', githubLogin: 'bob', discordUserId: '2', activeIssueCount: 0, expertiseTags: [], lastActiveAt: null },
    ]);
    mockChatCreate.mockRejectedValue(new Error('openai down'));

    const result = await triagePr(BASE_INPUT);

    expect(result.summary).toBe('');
    expect(result.recommendedReviewers.map((r) => r.userId)).toEqual(['uB']);
    expect(result.riskTags).toEqual(
      expect.arrayContaining(['large-diff', 'touches-functions']),
    );
  });

  it('per-file history failure is skipped, not fatal', async () => {
    mockListFiles.mockResolvedValue([file('a.ts'), file('b.ts')]);
    mockListCommitsForPath
      .mockRejectedValueOnce(new Error('404'))
      .mockResolvedValueOnce([
        { sha: 's', authorLogin: 'bob', committedAt: '2026-06-01' },
      ]);
    mockReadTeamState.mockResolvedValue([
      { userId: 'uB', name: 'Bob', githubLogin: 'bob', discordUserId: '2', activeIssueCount: 0, expertiseTags: [], lastActiveAt: null },
    ]);

    const result = await triagePr(BASE_INPUT);

    expect(result.recommendedReviewers.map((r) => r.userId)).toEqual(['uB']);
  });

  it('no candidates → empty reviewers, no throw', async () => {
    mockListFiles.mockResolvedValue([file('a.ts')]);
    mockListCommitsForPath.mockResolvedValue([]);
    mockReadTeamState.mockResolvedValue([]);

    const result = await triagePr(BASE_INPUT);

    expect(result.recommendedReviewers).toEqual([]);
  });
});
