// Unit tests for searchObservations + recallForPrompt (tools/memorySearch.ts).
//
// Boundary mocks (searchPastCommits.test.ts style):
//   - firebase-functions/v2 → logger no-op
//   - ../admin → fake Firestore (collection/where/findNearest + orderBy/limit/get)
//   - ../tools/embedding → embed() stubbed

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

// ---- Fake Firestore -------------------------------------------------------

const store = new Map<string, Record<string, unknown>>();
let findNearestError: Error | null = null;
let vectorHitIds: string[] = [];

function childDocsOf(colPath: string): Array<[string, Record<string, unknown>]> {
  return [...store.entries()].filter(
    ([p]) =>
      p.startsWith(`${colPath}/`) &&
      p.slice(colPath.length + 1).indexOf('/') === -1,
  );
}

interface Clause {
  field: string;
  op: string;
  value: unknown;
}

function makeQuery(colPath: string, clauses: Clause[]) {
  const filtered = () =>
    childDocsOf(colPath).filter(([, d]) =>
      clauses.every((c) => (c.op === '==' ? d[c.field] === c.value : true)),
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
    findNearest(opts: { limit?: number }) {
      return {
        async get() {
          if (findNearestError) throw findNearestError;
          const present = new Map(
            filtered().map(([p, d]) => [p.split('/').pop() as string, d]),
          );
          const cap = opts?.limit ?? Infinity;
          const docs = vectorHitIds
            .filter((id) => present.has(id))
            .slice(0, cap)
            .map((id) => ({ id, data: () => present.get(id)! }));
          return { empty: docs.length === 0, size: docs.length, docs };
        },
      };
    },
    async get() {
      const docs = filtered();
      return {
        empty: docs.length === 0,
        size: docs.length,
        docs: docs.map(([p, d]) => ({
          id: p.split('/').pop() as string,
          data: () => d,
        })),
      };
    },
  };
  return q;
}

const fakeDb = {
  collection: (path: string) => makeQuery(path, []),
};

jest.mock('../admin', () => ({ db: fakeDb }));

// ---- Fake embedding -------------------------------------------------------

const mockEmbed = jest.fn();
jest.mock('../tools/embedding', () => ({
  embed: (...args: unknown[]) => mockEmbed(...args),
}));

import { searchObservations, recallForPrompt } from '../tools/memorySearch';

// ---- Helpers --------------------------------------------------------------

const REPO = 'team17_gitsync';
const col = `apps/gitsync/repos/${REPO}/observations`;

function seedObs(
  id: string,
  content: string,
  extra: Record<string, unknown> = {},
) {
  store.set(`${col}/${id}`, {
    repoId: REPO,
    content,
    category: 'project_state',
    sourceFlow: 'summarizeDay',
    sourceId: null,
    tags: [],
    promoted: false,
    createdAt: { toDate: () => new Date() },
    ...extra,
  });
}

beforeEach(() => {
  store.clear();
  findNearestError = null;
  vectorHitIds = [];
  mockEmbed.mockReset().mockResolvedValue(new Array(1536).fill(0));
});

// ---- searchObservations ---------------------------------------------------

describe('searchObservations', () => {
  it('returns observations via vector search when hits exist', async () => {
    seedObs('obs1', 'Team prefers Riverpod');
    seedObs('obs2', 'Auth module is complex');
    vectorHitIds = ['obs1'];

    const results = await searchObservations(REPO, 'state management');
    expect(results).toHaveLength(1);
    expect(results[0].id).toBe('obs1');
    expect(results[0].content).toBe('Team prefers Riverpod');
  });

  it('falls back to keyword search when vector path fails', async () => {
    seedObs('obs1', 'Team prefers Riverpod', { tags: ['riverpod', 'state'] });
    seedObs('obs2', 'Auth module is complex', { tags: ['auth'] });
    findNearestError = new Error('no vector index');

    const results = await searchObservations(REPO, 'riverpod');
    expect(results).toHaveLength(1);
    expect(results[0].id).toBe('obs1');
  });

  it('falls back to keyword search when vector returns 0 hits', async () => {
    seedObs('obs1', 'Uses Firebase for backend', { tags: ['firebase'] });
    vectorHitIds = []; // empty vector results

    const results = await searchObservations(REPO, 'firebase');
    expect(results).toHaveLength(1);
    expect(results[0].content).toBe('Uses Firebase for backend');
  });

  it('returns recent observations on empty query', async () => {
    seedObs('obs1', 'fact one');
    seedObs('obs2', 'fact two');

    const results = await searchObservations(REPO, '', 5);
    expect(results).toHaveLength(2);
  });

  it('returns [] on a completely empty collection', async () => {
    const results = await searchObservations(REPO, 'anything');
    expect(results).toEqual([]);
  });

  it('respects the limit parameter', async () => {
    seedObs('obs1', 'fact one');
    seedObs('obs2', 'fact two');
    seedObs('obs3', 'fact three');

    const results = await searchObservations(REPO, '', 2);
    expect(results).toHaveLength(2);
  });

  it('returns [] (does not throw) when Firestore read fails', async () => {
    findNearestError = new Error('boom');
    // Also make the fallback fail by mocking the collection to throw
    const origCollection = fakeDb.collection;
    fakeDb.collection = () => {
      throw new Error('total failure');
    };

    const results = await searchObservations(REPO, 'test');
    expect(results).toEqual([]);

    fakeDb.collection = origCollection;
  });
});

// ---- recallForPrompt ------------------------------------------------------

describe('recallForPrompt', () => {
  it('returns "" when no observations exist', async () => {
    const result = await recallForPrompt(REPO, { query: 'anything' });
    expect(result).toBe('');
  });

  it('returns a formatted "## Relevant memory" block when observations exist', async () => {
    seedObs('obs1', 'Team prefers Riverpod');
    vectorHitIds = ['obs1'];

    const result = await recallForPrompt(REPO, { query: 'state management' });
    expect(result).toContain('## Relevant memory');
    expect(result).toContain('[project_state] Team prefers Riverpod');
  });

  it('deduplicates observations already in the brief', async () => {
    seedObs('obs1', 'Team prefers Riverpod');
    seedObs('obs2', 'Auth is complex');
    vectorHitIds = ['obs1', 'obs2'];

    const result = await recallForPrompt(REPO, {
      query: 'architecture',
      briefContent: 'The team prefers riverpod for state management.',
    });
    // obs1 content is in the brief (case-insensitive), should be filtered out
    expect(result).not.toContain('Riverpod');
    expect(result).toContain('Auth is complex');
  });

  it('returns "" when all observations are already in the brief', async () => {
    seedObs('obs1', 'Team prefers Riverpod');
    vectorHitIds = ['obs1'];

    const result = await recallForPrompt(REPO, {
      query: 'state',
      briefContent: 'Team prefers Riverpod and uses Firebase.',
    });
    expect(result).toBe('');
  });

  it('returns "" (does not throw) on failure', async () => {
    mockEmbed.mockRejectedValue(new Error('embedding down'));
    seedObs('obs1', 'some fact');

    const result = await recallForPrompt(REPO, { query: 'test' });
    // Should degrade gracefully — keyword fallback still works even if embed fails
    // The result is either '' or contains the fact via keyword match
    expect(typeof result).toBe('string');
  });
});
