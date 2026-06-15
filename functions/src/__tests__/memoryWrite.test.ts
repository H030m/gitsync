// Unit tests for writeObservation (tools/memoryWrite.ts).
//
// Boundary mocks (projectBrief.test.ts style):
//   - firebase-functions/v2 → logger no-op
//   - firebase-admin/firestore → FieldValue sentinels
//   - ../admin → fake Firestore (collection/add)
//   - ../tools/embedding → embedToFieldValue stubbed

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

jest.mock('firebase-admin/firestore', () => ({
  FieldValue: {
    serverTimestamp: () => '__ts__',
    vector: (v: number[]) => v,
  },
}));

// ---- Fake Firestore -------------------------------------------------------

const addedDocs: Array<{ path: string; data: Record<string, unknown> }> = [];
let addError: Error | null = null;

const fakeDb = {
  collection: (path: string) => ({
    async add(data: Record<string, unknown>) {
      if (addError) throw addError;
      addedDocs.push({ path, data });
      return { id: 'obs-1' };
    },
  }),
};

jest.mock('../admin', () => ({ db: fakeDb }));

// ---- Fake embedding -------------------------------------------------------

const mockEmbedToFieldValue = jest.fn();
jest.mock('../tools/embedding', () => ({
  embedToFieldValue: (...args: unknown[]) => mockEmbedToFieldValue(...args),
}));

import { writeObservation } from '../tools/memoryWrite';

const REPO = 'team17_gitsync';

beforeEach(() => {
  addedDocs.length = 0;
  addError = null;
  mockEmbedToFieldValue.mockReset().mockResolvedValue([0.1, 0.2]);
});

describe('writeObservation', () => {
  it('writes a doc with embedding and returns the doc id', async () => {
    const id = await writeObservation(REPO, {
      content: 'Team prefers Riverpod over Bloc',
      category: 'convention',
      sourceFlow: 'askRepo',
      sourceId: 'run-123',
      tags: ['riverpod', 'bloc'],
    });

    expect(id).toBe('obs-1');
    expect(addedDocs).toHaveLength(1);
    expect(addedDocs[0].path).toBe(`apps/gitsync/repos/${REPO}/observations`);
    expect(addedDocs[0].data).toMatchObject({
      content: 'Team prefers Riverpod over Bloc',
      category: 'convention',
      sourceFlow: 'askRepo',
      sourceId: 'run-123',
      tags: ['riverpod', 'bloc'],
      promoted: false,
      repoId: REPO,
    });
    expect(mockEmbedToFieldValue).toHaveBeenCalledWith('Team prefers Riverpod over Bloc');
  });

  it('truncates content to 500 chars', async () => {
    const longContent = 'x'.repeat(600);
    await writeObservation(REPO, {
      content: longContent,
      category: 'project_state',
      sourceFlow: 'summarizeDay',
    });

    expect(addedDocs[0].data.content).toHaveLength(500);
  });

  it('returns null on empty content', async () => {
    const id = await writeObservation(REPO, {
      content: '   ',
      category: 'blocker',
      sourceFlow: 'summarizeDay',
    });

    expect(id).toBeNull();
    expect(addedDocs).toHaveLength(0);
  });

  it('returns null (does not throw) on Firestore write failure', async () => {
    addError = new Error('permission denied');
    const id = await writeObservation(REPO, {
      content: 'some fact',
      category: 'lesson',
      sourceFlow: 'askRepo',
    });

    expect(id).toBeNull();
  });

  it('returns null (does not throw) on embedding failure', async () => {
    mockEmbedToFieldValue.mockRejectedValue(new Error('embedding down'));
    const id = await writeObservation(REPO, {
      content: 'some fact',
      category: 'lesson',
      sourceFlow: 'askRepo',
    });

    expect(id).toBeNull();
  });

  it('defaults tags to [] and sourceId to null when omitted', async () => {
    await writeObservation(REPO, {
      content: 'a fact',
      category: 'project_state',
      sourceFlow: 'summarizeDay',
    });

    expect(addedDocs[0].data.tags).toEqual([]);
    expect(addedDocs[0].data.sourceId).toBeNull();
  });
});
