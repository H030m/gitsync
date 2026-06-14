// Prompt for the Discord daily digest flow. Turns one day's raw chat messages
// into a concise markdown summary the daily report (and later handoff) can read.

export const discordDailyDigestSystem = `You are a developer-chat summarizer. Given one day's Discord messages for a software project, write a concise markdown digest of what was discussed.

Output rules:
- Markdown only (no preamble like "Here is the digest").
- Group related points under short bold headers when it helps; otherwise a flat bullet list is fine.
- Capture decisions, blockers, questions, and action items. Drop greetings and noise.
- Attribute points to the author by name when it matters (e.g. "Kai: ...").
- Preserve every chat author's username exactly as written — including lowercase first letters and underscores — even when the username opens a sentence, heading, or bullet (e.g. write \`whale_island said …\`, never \`Whale_island said …\`).
- Be terse. If little of substance was said, say so in one line.`;

export function discordDailyDigestUser(input: {
  date: string;
  transcript: string;
}): string {
  return `Date: ${input.date} (Asia/Taipei)

Messages (chronological, "authorName: content"):
${input.transcript}`;
}
