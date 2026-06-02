// Unit tests for the githubWebhook onRequest handler.
//
// Boundary mocks (testing-guidelines.md):
//   - firebase-functions/v2/https → onRequest returns the raw handler so we can
//     invoke it directly with fake req/res.
//   - firebase-functions/v2 → logger is a no-op.
//   - ../admin → db is a hand-rolled fake Firestore (doc/get/set/batch).
//   - ../tools/idempotency → markIdempotent is a mock (controls dup branch).
//
// A real HMAC is computed in the tests to exercise the verify path.

import { createHmac } from 'node:crypto';

// ---- Mocks ----------------------------------------------------------------

jest.mock('firebase-functions/v2/https', () => ({
  // onRequest just hands back the inner handler for direct invocation.
  onRequest: (_opts: unknown, handler: unknown) => handler,
}));

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

const mockMarkIdempotent = jest.fn();
jest.mock('../tools/idempotency', () => ({
  markIdempotent: (...args: unknown[]) => mockMarkIdempotent(...args),
}));

// ---- Fake Firestore -------------------------------------------------------

const store = new Map<string, Record<string, unknown>>();

function makeDocRef(path: string) {
  return {
    path,
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
    async set(data: Record<string, unknown>, options?: { merge?: boolean }) {
      if (options?.merge) {
        store.set(path, { ...(store.get(path) ?? {}), ...data });
      } else {
        store.set(path, data);
      }
    },
  };
}

const fakeDb = {
  doc: (path: string) => makeDocRef(path),
  batch: () => {
    const writes: Array<{ path: string; data: Record<string, unknown> }> = [];
    return {
      set(ref: { path: string }, data: Record<string, unknown>) {
        writes.push({ path: ref.path, data });
      },
      async commit() {
        for (const w of writes) store.set(w.path, w.data);
      },
    };
  },
};

jest.mock('../admin', () => ({
  db: fakeDb,
  REGION: 'asia-east1',
}));

jest.mock('firebase-admin/firestore', () => ({
  FieldValue: {
    serverTimestamp: () => '__serverTimestamp__',
  },
}));

// Import after mocks are registered.
import { githubWebhook } from '../handlers/githubWebhook';

// ---- Helpers --------------------------------------------------------------

const SECRET = 'topsecret';
const OWNER = 'octocat';
const REPO = 'hello';
const REPO_ID = `${OWNER}_${REPO}`;

interface FakeRes {
  statusCode?: number;
  body?: unknown;
  status: (code: number) => FakeRes;
  send: (b?: unknown) => FakeRes;
}

function makeRes(): FakeRes {
  const res: FakeRes = {
    status(code: number) {
      res.statusCode = code;
      return res;
    },
    send(b?: unknown) {
      res.body = b;
      return res;
    },
  };
  return res;
}

function sign(rawBody: Buffer): string {
  return 'sha256=' + createHmac('sha256', SECRET).update(rawBody).digest('hex');
}

interface ReqOpts {
  body: Record<string, unknown>;
  event: string;
  delivery?: string;
  signature?: string | null; // null = omit; undefined = auto-correct
}

function makeReq(opts: ReqOpts) {
  const rawBody = Buffer.from(JSON.stringify(opts.body));
  const headers: Record<string, string | undefined> = {
    'x-github-event': opts.event,
    'x-github-delivery': opts.delivery ?? 'delivery-1',
  };
  if (opts.signature === null) {
    headers['x-hub-signature-256'] = undefined;
  } else if (opts.signature === undefined) {
    headers['x-hub-signature-256'] = sign(rawBody);
  } else {
    headers['x-hub-signature-256'] = opts.signature;
  }
  return {
    body: opts.body,
    rawBody,
    header: (name: string) => headers[name.toLowerCase()],
  };
}

const handler = githubWebhook as unknown as (
  req: unknown,
  res: FakeRes,
) => Promise<void>;

function pushBody(extra?: Partial<Record<string, unknown>>) {
  return {
    ref: 'refs/heads/main',
    repository: { name: REPO, default_branch: 'main', owner: { login: OWNER } },
    commits: [
      {
        id: 'abc123',
        message: 'fix: something',
        url: 'https://github.com/octocat/hello/commit/abc123',
        timestamp: '2026-06-02T00:00:00Z',
        author: { name: 'Octo', email: 'octo@example.com', username: 'octocat' },
        added: ['a.ts'],
        removed: [],
        modified: ['b.ts'],
      },
    ],
    ...extra,
  };
}

function prBody(extra?: Partial<Record<string, unknown>>) {
  return {
    action: 'closed',
    repository: { name: REPO, owner: { login: OWNER } },
    pull_request: {
      number: 7,
      title: 'Add feature',
      body: 'closes #3',
      merged: true,
      merged_at: '2026-06-02T00:00:00Z',
      head: { ref: 'feature' },
      base: { ref: 'main' },
    },
    ...extra,
  };
}

function issueBody(extra?: Partial<Record<string, unknown>>) {
  return {
    action: 'closed',
    repository: { name: REPO, owner: { login: OWNER } },
    issue: { number: 3, state: 'closed', title: 'Bug' },
    ...extra,
  };
}

beforeEach(() => {
  store.clear();
  mockMarkIdempotent.mockReset();
  mockMarkIdempotent.mockResolvedValue(true);
  store.set(`apps/gitsync/repos/${REPO_ID}`, { webhookSecret: SECRET });
});

// ---- Tests ----------------------------------------------------------------

describe('githubWebhook', () => {
  it('valid push signature → 200 + commit doc written', async () => {
    const req = makeReq({ body: pushBody(), event: 'push' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ ok: true });
    const commit = store.get(`apps/gitsync/repos/${REPO_ID}/commits/abc123`);
    expect(commit).toMatchObject({
      repoId: REPO_ID,
      sha: 'abc123',
      message: 'fix: something',
      filesChanged: 2,
      // Stored under canonical `login` (payload's `author.username` → `login`).
      author: { name: 'Octo', login: 'octocat' },
    });
  });

  it('invalid signature → 401, no write', async () => {
    const req = makeReq({
      body: pushBody(),
      event: 'push',
      signature: 'sha256=deadbeef',
    });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(401);
    expect(store.get(`apps/gitsync/repos/${REPO_ID}/commits/abc123`)).toBeUndefined();
    expect(mockMarkIdempotent).not.toHaveBeenCalled();
  });

  it('missing signature header → 401, no write', async () => {
    const req = makeReq({ body: pushBody(), event: 'push', signature: null });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(401);
    expect(store.get(`apps/gitsync/repos/${REPO_ID}/commits/abc123`)).toBeUndefined();
  });

  it('unknown repo / missing secret → 401', async () => {
    store.delete(`apps/gitsync/repos/${REPO_ID}`);
    const req = makeReq({ body: pushBody(), event: 'push' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(401);
  });

  it('duplicate delivery (markIdempotent→false) → 200 dup, no write', async () => {
    mockMarkIdempotent.mockResolvedValue(false);
    const req = makeReq({ body: pushBody(), event: 'push' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ ok: true, dup: true });
    expect(store.get(`apps/gitsync/repos/${REPO_ID}/commits/abc123`)).toBeUndefined();
  });

  it('push to non-default branch → 200, no commit doc', async () => {
    const req = makeReq({
      body: pushBody({ ref: 'refs/heads/feature' }),
      event: 'push',
    });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    expect(store.get(`apps/gitsync/repos/${REPO_ID}/commits/abc123`)).toBeUndefined();
  });

  it('PR merged → pullRequests doc written', async () => {
    const req = makeReq({ body: prBody(), event: 'pull_request' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    const pr = store.get(`apps/gitsync/repos/${REPO_ID}/pullRequests/7`);
    expect(pr).toMatchObject({
      repoId: REPO_ID,
      number: 7,
      title: 'Add feature',
      body: 'closes #3',
      state: 'merged',
      headBranch: 'feature',
      baseBranch: 'main',
      commitShas: [],
    });
  });

  it('PR closed but not merged → no write', async () => {
    const body = prBody();
    (body.pull_request as Record<string, unknown>).merged = false;
    const req = makeReq({ body, event: 'pull_request' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    expect(store.get(`apps/gitsync/repos/${REPO_ID}/pullRequests/7`)).toBeUndefined();
  });

  it('issue event → issues doc upserted', async () => {
    const req = makeReq({ body: issueBody(), event: 'issues' });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    const issue = store.get(`apps/gitsync/repos/${REPO_ID}/issues/3`);
    expect(issue).toMatchObject({
      repoId: REPO_ID,
      number: 3,
      state: 'closed',
      title: 'Bug',
      action: 'closed',
    });
  });

  it('unknown event → 200, no write', async () => {
    const req = makeReq({
      body: { repository: { name: REPO, owner: { login: OWNER } } },
      event: 'star',
    });
    const res = makeRes();
    await handler(req, res);

    expect(res.statusCode).toBe(200);
    expect(res.body).toMatchObject({ ok: true });
  });
});
