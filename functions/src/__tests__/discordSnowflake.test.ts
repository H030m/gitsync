import { snowflakeForTaipeiDate } from '../tools/discordSnowflake';

describe('snowflakeForTaipeiDate', () => {
  it('produces a numeric string that round-trips to roughly the day start', () => {
    const sf = snowflakeForTaipeiDate('2026-06-03');
    expect(sf).toMatch(/^\d+$/);

    // Decode: ms = (snowflake >> 22) + DISCORD_EPOCH. Should be ~ Taipei
    // 2026-06-03 00:00 = 2026-06-02T16:00:00Z (minus the 1ms inclusivity nudge).
    const DISCORD_EPOCH_MS = 1420070400000n;
    const ms = Number((BigInt(sf) >> 22n) + DISCORD_EPOCH_MS);
    const expected = Date.parse('2026-06-02T16:00:00Z');
    expect(Math.abs(ms - expected)).toBeLessThanOrEqual(2);
  });

  it('is monotonic across days', () => {
    const a = BigInt(snowflakeForTaipeiDate('2026-06-03'));
    const b = BigInt(snowflakeForTaipeiDate('2026-06-04'));
    expect(b > a).toBe(true);
  });

  it('rejects malformed dates', () => {
    expect(() => snowflakeForTaipeiDate('2026-6-3')).toThrow();
    expect(() => snowflakeForTaipeiDate('nope')).toThrow();
  });
});
