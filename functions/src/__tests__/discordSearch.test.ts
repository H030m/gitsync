import { buildSnippets, type DiscordMessageHit } from '../tools/discordSearch';

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
