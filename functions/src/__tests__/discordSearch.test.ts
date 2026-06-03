import { rankMessages, type DiscordMessageHit } from '../tools/discordSearch';

function msg(id: string, content: string): DiscordMessageHit {
  return { messageId: id, channelId: 'c1', authorName: 'a', content, timestamp: null };
}

// docs arrive newest-first (Firestore orderBy timestamp desc).
const docs: DiscordMessageHit[] = [
  msg('m3', 'Floats are fine, zod schema already allows numbers'),
  msg('m2', 'For breakdownTask, are we okay treating estimatedHours as floats?'),
  msg('m1', "I'll start the GitHub OAuth piece tonight"),
];

describe('rankMessages', () => {
  it('ranks by number of distinct query terms matched', () => {
    const out = rankMessages(docs, 'oauth github', 10);
    expect(out[0].messageId).toBe('m1');
  });

  it('returns the most relevant first when multiple match', () => {
    const out = rankMessages(docs, 'floats schema', 10);
    // m3 contains both "floats" and "schema" (score 2) → ahead of m2 (score 1).
    expect(out[0].messageId).toBe('m3');
    expect(out.map((d) => d.messageId)).toContain('m2');
  });

  it('respects the cap', () => {
    expect(rankMessages(docs, 'floats', 1)).toHaveLength(1);
  });

  it('degrades to most-recent when nothing matches', () => {
    const out = rankMessages(docs, 'kubernetes deployment', 2);
    expect(out).toHaveLength(2);
    expect(out[0].messageId).toBe('m3'); // newest first
  });

  it('returns most-recent when the query has no usable terms', () => {
    const out = rankMessages(docs, '   ??  ', 2);
    expect(out.map((d) => d.messageId)).toEqual(['m3', 'm2']);
  });
});
