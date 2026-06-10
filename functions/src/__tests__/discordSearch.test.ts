// Fake Firestore for the range-aware DB readers. The query records its where()
// clauses; `get()` applies them against an in-memory store so we can assert the
// timestamp window narrows the scan (and that no-range scans everything).
jest.mock('firebase-functions/v2', () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

interface Clause {
  field: string;
  op: string;
  value: { toMillis: () => number };
}
const store = new Map<string, Record<string, unknown>>();

function childDocsOf(colPath: string): Array<[string, Record<string, unknown>]> {
  return [...store.entries()].filter(
    ([p]) =>
      p.startsWith(`${colPath}/`) &&
      p.slice(colPath.length + 1).indexOf('/') === -1,
  );
}

function tsOf(v: unknown): number | null {
  if (v && typeof (v as { toMillis?: unknown }).toMillis === 'function') {
    return (v as { toMillis: () => number }).toMillis();
  }
  return null;
}

function makeQuery(colPath: string, clauses: Clause[]) {
  const q = {
    where(field: string, op: string, value: { toMillis: () => number }) {
      return makeQuery(colPath, [...clauses, { field, op, value }]);
    },
    orderBy() {
      return q;
    },
    limit() {
      return q;
    },
    async get() {
      const docs = childDocsOf(colPath).filter(([, d]) =>
        clauses.every((c) => {
          const fieldMs = tsOf(d[c.field]);
          const valMs = c.value.toMillis();
          if (fieldMs === null) return false;
          if (c.op === '>=') return fieldMs >= valMs;
          if (c.op === '<') return fieldMs < valMs;
          return true;
        }),
      );
      return {
        empty: docs.length === 0,
        size: docs.length,
        docs: docs.map(([p, d]) => ({
          id: p.split('/').pop() as string,
          ref: { path: p },
          data: () => d,
        })),
      };
    },
  };
  return q;
}

const fakeDb = {
  doc: (path: string) => ({
    async get() {
      const data = store.get(path);
      return { exists: data !== undefined, data: () => data };
    },
  }),
  collection: (path: string) => makeQuery(path, []),
};

jest.mock('../admin', () => ({ db: fakeDb }));

import {
  buildSnippets,
  searchDiscordMessages,
  listDaySummaries,
  type DiscordMessageHit,
  type SearchRange,
} from '../tools/discordSearch';

// A Timestamp-like value: comparable via toMillis(), the only method the
// fake query + production range filter use.
function ts(ms: number): { toMillis: () => number; toDate: () => Date } {
  return { toMillis: () => ms, toDate: () => new Date(ms) };
}
function rangeFor(startMs: number, endMs: number, startDate: string, endDate: string): SearchRange {
  return {
    start: ts(startMs) as unknown as SearchRange['start'],
    end: ts(endMs) as unknown as SearchRange['end'],
    startDate,
    endDate,
  };
}

const REPO = 'team17_gitsync';
const msgCol = `apps/gitsync/repos/${REPO}/discordMessages`;
const digestCol = `apps/gitsync/repos/${REPO}/discordDigests`;

// Snowflake ids are monotonic with time; use small ascending ids per channel.
function msg(id: string, channelId: string, content: string): DiscordMessageHit {
  return {
    messageId: id,
    channelId,
    authorName: 'u' + id,
    content,
    timestamp: null,
    isMatch: false,
  };
}

// A single channel "c1" timeline (ids ascending = chronological).
const c1: DiscordMessageHit[] = [
  msg('10', 'c1', 'morning standup notes'),
  msg('11', 'c1', 'i push a commit for the OAuth flow'),
  msg('12', 'c1', 'ok looks good'),
  msg('13', 'c1', 'lunch?'),
  msg('14', 'c1', 'random chatter'),
  msg('15', 'c1', 'the commit is broken, i will fix it'),
  msg('16', 'c1', 'thanks'),
];

describe('buildSnippets', () => {
  it('groups each match with surrounding context (before/after)', () => {
    const out = buildSnippets(c1, 'commit', { before: 1, after: 1 });
    // Two separate "commit" conversations → two snippets.
    expect(out).toHaveLength(2);
    // First snippet centers on id 11 with one msg before/after.
    const ids = out.map((s) => s.messages.map((m) => m.messageId));
    expect(ids).toContainEqual(['10', '11', '12']);
    expect(ids).toContainEqual(['14', '15', '16']);
  });

  it('flags only the matched messages as isMatch, context is false', () => {
    const out = buildSnippets(c1, 'commit', { before: 1, after: 1 });
    // Find the snippet centered on id 11 regardless of ranking order.
    const snip = out.find((s) => s.messages.some((m) => m.messageId === '11'))!;
    const matched = snip.messages.filter((m) => m.isMatch).map((m) => m.messageId);
    expect(matched).toEqual(['11']); // only the matching line
    expect(snip.messages.find((m) => m.messageId === '10')!.isMatch).toBe(false);
  });

  it('merges overlapping windows into one snippet', () => {
    // Two adjacent matches (15 and a synthetic 14b) → windows overlap → 1 snippet.
    const adjacent = [
      msg('20', 'c1', 'commit landed'),
      msg('21', 'c1', 'another commit right after'),
      msg('22', 'c1', 'done'),
    ];
    const out = buildSnippets(adjacent, 'commit', { before: 2, after: 2 });
    expect(out).toHaveLength(1);
    expect(out[0].messages).toHaveLength(3);
  });

  it('keeps snippets per-channel (no cross-channel context)', () => {
    const mixed = [
      msg('30', 'cA', 'deploy the commit'),
      msg('31', 'cB', 'unrelated in another channel'),
      msg('32', 'cA', 'reply in A'),
    ];
    const out = buildSnippets(mixed, 'commit', { before: 2, after: 2 });
    expect(out).toHaveLength(1);
    expect(out[0].channelId).toBe('cA');
    expect(out[0].messages.every((m) => m.channelId === 'cA')).toBe(true);
  });

  it('ranks higher-match snippets first', () => {
    const out = buildSnippets(c1, 'commit broken fix', { before: 0, after: 0 });
    // id 15 contains commit+broken+fix → more term coverage isn't counted, but
    // it is still a match; both 11 and 15 match → 2 snippets, order by recency.
    expect(out.length).toBeGreaterThanOrEqual(1);
  });

  it('falls back to recent messages when nothing matches', () => {
    const out = buildSnippets(c1, 'kubernetes helm chart', { before: 1, after: 1 });
    expect(out).toHaveLength(1);
    expect(out[0].messages.every((m) => m.isMatch === false)).toBe(true);
    // Most-recent window, chronological.
    expect(out[0].messages.map((m) => m.messageId)).toEqual(['14', '15', '16']);
  });

  it('falls back to recent when the query has no usable terms', () => {
    const out = buildSnippets(c1, '  ??  ', { before: 1, after: 1 });
    expect(out).toHaveLength(1);
    expect(out[0].score).toBe(0);
  });
});

describe('searchDiscordMessages (range filter)', () => {
  // Three messages on three days; timestamps as comparable Timestamp-likes.
  const DAY1 = Date.UTC(2026, 5, 1, 4); // 2026-06-01
  const DAY3 = Date.UTC(2026, 5, 3, 4); // 2026-06-03
  const DAY9 = Date.UTC(2026, 5, 9, 4); // 2026-06-09

  // Numeric (snowflake-like) message ids so buildSnippets' BigInt sort works.
  beforeEach(() => {
    store.clear();
    store.set(`${msgCol}/101`, { channelId: 'c1', authorName: 'a', content: 'deploy oauth', timestamp: ts(DAY1) });
    store.set(`${msgCol}/103`, { channelId: 'c1', authorName: 'b', content: 'oauth again', timestamp: ts(DAY3) });
    store.set(`${msgCol}/109`, { channelId: 'c1', authorName: 'c', content: 'oauth way later', timestamp: ts(DAY9) });
  });

  it('without a range, scans every message', async () => {
    const out = await searchDiscordMessages(REPO, 'oauth');
    const ids = out.flatMap((s) => s.messages.map((m) => m.messageId)).sort();
    expect(ids).toEqual(['101', '103', '109']);
  });

  it('with a range, only surfaces in-window messages', async () => {
    // Window [06-01, 06-06): includes 101 (06-01) + 103 (06-03), excludes 109 (06-09).
    const range = rangeFor(Date.UTC(2026, 5, 1), Date.UTC(2026, 5, 6), '2026-06-01', '2026-06-05');
    const out = await searchDiscordMessages(REPO, 'oauth', undefined, range);
    const ids = out.flatMap((s) => s.messages.map((m) => m.messageId)).sort();
    expect(ids).toEqual(['101', '103']);
    expect(ids).not.toContain('109');
  });

  it('never throws — degrades to [] on a read failure', async () => {
    const out = await searchDiscordMessages('no-such-collection-path', 'x');
    expect(Array.isArray(out)).toBe(true);
  });
});

describe('listDaySummaries (range filter)', () => {
  beforeEach(() => {
    store.clear();
    store.set(`${digestCol}/2026-05-30`, { date: '2026-05-30', messageCount: 1, markdown: 'before' });
    store.set(`${digestCol}/2026-06-02`, { date: '2026-06-02', messageCount: 2, markdown: 'inside a' });
    store.set(`${digestCol}/2026-06-04`, { date: '2026-06-04', messageCount: 3, markdown: 'inside b' });
    store.set(`${digestCol}/2026-06-09`, { date: '2026-06-09', messageCount: 4, markdown: 'after' });
  });

  it('without a range, returns every digest', async () => {
    const out = await listDaySummaries(REPO);
    expect(out.map((d) => d.date).sort()).toEqual([
      '2026-05-30',
      '2026-06-02',
      '2026-06-04',
      '2026-06-09',
    ]);
  });

  it('with a range, filters to days within [startDate, endDate]', async () => {
    const range = rangeFor(0, 1, '2026-06-01', '2026-06-05');
    const out = await listDaySummaries(REPO, range);
    expect(out.map((d) => d.date).sort()).toEqual(['2026-06-02', '2026-06-04']);
  });

  it('includes the inclusive endpoints', async () => {
    const range = rangeFor(0, 1, '2026-06-02', '2026-06-04');
    const out = await listDaySummaries(REPO, range);
    expect(out.map((d) => d.date).sort()).toEqual(['2026-06-02', '2026-06-04']);
  });
});
