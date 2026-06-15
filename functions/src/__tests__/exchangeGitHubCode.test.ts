// Unit tests for the exchangeGitHubCode callable. Boundary mocks per
// testing-guidelines: onCall → raw handler, ../admin → in-memory fake,
// ../services/githubClient.exchangeOAuthCode → jest.mock, ../config → constants
// + a fake secret.

class FakeHttpsError extends Error {
  constructor(public code: string, message: string) {
    super(message);
    this.name = 'HttpsError';
  }
}

jest.mock('firebase-functions/v2/https', () => ({
  onCall: (_opts: unknown, handler: unknown) => handler,
  HttpsError: FakeHttpsError,
}));
jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

// ---- Fake Firestore ---------------------------------------------------------

const store = new Map<string, Record<string, unknown>>();
const setSpy = jest.fn();

const fakeDb = {
  doc: (path: string) => ({
    path,
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
    async set(data: Record<string, unknown>, opts?: { merge?: boolean }) {
      setSpy(path, data, opts);
      store.set(path, { ...(store.get(path) ?? {}), ...data });
    },
  }),
};

jest.mock('../admin', () => ({ db: fakeDb, REGION: 'asia-east1' }));

jest.mock('../config', () => ({
  GITHUB_OAUTH_CLIENT_ID: 'test-client-id',
  githubOAuthClientSecret: { value: () => 'test-client-secret' },
}));

const mockExchange = jest.fn();
jest.mock('../services/githubClient', () => ({
  exchangeOAuthCode: (...args: unknown[]) => mockExchange(...args),
}));

import { exchangeGitHubCode } from '../handlers/exchangeGitHubCode';

type Handler = (req: {
  auth: { uid: string } | null;
  data: Record<string, unknown>;
}) => Promise<Record<string, unknown>>;
const handler = exchangeGitHubCode as unknown as Handler;

beforeEach(() => {
  store.clear();
  setSpy.mockClear();
  mockExchange.mockReset();
});

describe('exchangeGitHubCode', () => {
  it('rejects unauthenticated calls → failed-precondition', async () => {
    await expect(
      handler({ auth: null, data: { code: 'c', redirectUri: 'r' } }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(mockExchange).not.toHaveBeenCalled();
  });

  it('rejects a missing code → invalid-argument', async () => {
    await expect(
      handler({ auth: { uid: 'u1' }, data: { redirectUri: 'r' } }),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('rejects a missing redirectUri → invalid-argument', async () => {
    await expect(
      handler({ auth: { uid: 'u1' }, data: { code: 'c' } }),
    ).rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('success: exchanges code, writes token (merge), returns ok', async () => {
    mockExchange.mockResolvedValue({
      accessToken: 'gho_abc123',
      scope: 'repo,read:user',
      tokenType: 'bearer',
    });

    const res = await handler({
      auth: { uid: 'u1' },
      data: { code: 'the-code', redirectUri: 'gitsync://oauth/github' },
    });

    expect(res).toEqual({ ok: true });
    // Secret + client_id come from config, not the request.
    expect(mockExchange).toHaveBeenCalledWith({
      clientId: 'test-client-id',
      clientSecret: 'test-client-secret',
      code: 'the-code',
      redirectUri: 'gitsync://oauth/github',
    });
    // Token written to the canonical field with merge.
    expect(store.get('apps/gitsync/users/u1')).toEqual({
      githubAccessToken: 'gho_abc123',
    });
    expect(setSpy).toHaveBeenCalledWith(
      'apps/gitsync/users/u1',
      { githubAccessToken: 'gho_abc123' },
      { merge: true },
    );
    // The token is NEVER returned to the client.
    expect(res).not.toHaveProperty('githubAccessToken');
  });

  it('accepts space-separated scopes too', async () => {
    mockExchange.mockResolvedValue({
      accessToken: 'gho_x',
      scope: 'read:user repo gist',
      tokenType: 'bearer',
    });
    const res = await handler({
      auth: { uid: 'u2' },
      data: { code: 'c', redirectUri: 'r' },
    });
    expect(res).toEqual({ ok: true });
  });

  it('GitHub exchange error → failed-precondition, no token written', async () => {
    mockExchange.mockRejectedValue(new Error('bad_verification_code'));
    await expect(
      handler({ auth: { uid: 'u1' }, data: { code: 'c', redirectUri: 'r' } }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(store.get('apps/gitsync/users/u1')).toBeUndefined();
  });

  it('missing required scope → failed-precondition, no token written', async () => {
    mockExchange.mockResolvedValue({
      accessToken: 'gho_x',
      scope: 'read:user', // missing repo
      tokenType: 'bearer',
    });
    await expect(
      handler({ auth: { uid: 'u1' }, data: { code: 'c', redirectUri: 'r' } }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(store.get('apps/gitsync/users/u1')).toBeUndefined();
  });
});
