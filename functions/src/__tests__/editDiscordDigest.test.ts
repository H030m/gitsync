// Unit tests for editDiscordDigestFlow. Verifies the lock gate (refuses a
// locked digest), the not-found guard, and the happy-path AI rewrite + merge
// write. Boundaries mocked: ../admin (fake Firestore doc), ../config (OpenAI
// stub), firebase-admin/firestore (FieldValue), firebase-functions/v2 logger.

jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

jest.mock('firebase-admin/firestore', () => ({
  FieldValue: { serverTimestamp: () => '__ts__' },
}));

const setSpy = jest.fn();
let docData: Record<string, unknown> | undefined;

jest.mock('../admin', () => ({
  db: {
    doc: (_path: string) => ({
      async get() {
        return { exists: docData !== undefined, data: () => docData };
      },
      async set(data: Record<string, unknown>, opts: unknown) {
        setSpy(data, opts);
        docData = { ...(docData ?? {}), ...data };
      },
    }),
  },
  REGION: 'asia-east1',
}));

const createSpy = jest.fn(async () => ({
  choices: [{ message: { content: '# Revised\n- new bullet' } }],
}));

jest.mock('../config', () => ({
  getOpenAI: () => ({ chat: { completions: { create: createSpy } } }),
  MODELS: { fast: 'gpt-4o-mini' },
}));

import { editDiscordDigestFlow } from '../flows/editDiscordDigest';

describe('editDiscordDigestFlow', () => {
  beforeEach(() => {
    setSpy.mockClear();
    createSpy.mockClear();
    docData = undefined;
  });

  it('throws not-found when the digest does not exist', async () => {
    await expect(
      editDiscordDigestFlow({ repoId: 'r', date: '2026-06-03', instruction: 'x' }),
    ).rejects.toMatchObject({ code: 'not-found' });
    expect(createSpy).not.toHaveBeenCalled();
  });

  it('refuses to edit a locked digest (no OpenAI call, no write)', async () => {
    docData = { markdown: '# old', locked: true };
    await expect(
      editDiscordDigestFlow({ repoId: 'r', date: '2026-06-03', instruction: 'x' }),
    ).rejects.toMatchObject({ code: 'failed-precondition' });
    expect(createSpy).not.toHaveBeenCalled();
    expect(setSpy).not.toHaveBeenCalled();
  });

  it('rewrites an unlocked digest and merge-writes the result', async () => {
    docData = { markdown: '# old', locked: false };
    const out = await editDiscordDigestFlow({
      repoId: 'r',
      date: '2026-06-03',
      instruction: 'make it shorter',
    });
    expect(out.markdown).toBe('# Revised\n- new bullet');
    expect(createSpy).toHaveBeenCalledTimes(1);
    const [written, opts] = setSpy.mock.calls[0];
    expect(written).toMatchObject({
      markdown: '# Revised\n- new bullet',
      lastEditInstruction: 'make it shorter',
    });
    expect(opts).toEqual({ merge: true });
  });
});
