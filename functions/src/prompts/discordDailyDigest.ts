// Prompt for the Discord daily digest flow. Turns one day's raw chat messages
// into a concise markdown summary the daily report (and later handoff) can read.
// Common rules (identity / grounding / no-fluff) come from the top-level base.
import { buildSystemPrompt } from './baseSystem';

const discordDailyDigestBody = `Your task: given one day's Discord messages for a software project, write a concise markdown digest of what was discussed.

Output rules:
- Markdown only (no preamble like "Here is the digest").
- Prefer a single flat bullet list. Use sub-headers sparingly or not at all — only add one if the day's discussion is large and genuinely splits into distinct topics.
- Capture decisions, blockers, questions, and action items. Drop greetings and noise.
- Attribute points to the author by name when it matters (e.g. "Kai: ...").
- Preserve every chat author's username exactly as written — including lowercase first letters and underscores — even when the username opens a sentence, heading, or bullet (e.g. write \`whale_island said …\`, never \`Whale_island said …\`).
- Write the digest in Traditional Chinese (繁體中文), regardless of the language the messages are written in. (Author usernames stay exactly as written; proper nouns / IDs are kept as-is.)
- Be terse. If little of substance was said, say so in one line.`;

export const discordDailyDigestSystem = buildSystemPrompt({
  agentBody: discordDailyDigestBody,
});

export function discordDailyDigestUser(input: {
  date: string;
  transcript: string;
}): string {
  return `Date: ${input.date} (Asia/Taipei)

Messages (chronological, "authorName: content"):
${input.transcript}`;
}
