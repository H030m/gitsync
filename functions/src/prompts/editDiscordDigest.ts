// Prompt for editDiscordDigestFlow — revises an existing Discord digest in
// place according to a natural-language instruction (from the app's adjust
// field or the bot's /gitsync-digest command).

export const editDiscordDigestSystem = `You revise an existing Markdown summary of a software team's Discord chat according to the user's instruction.

Rules:
- Output ONLY the revised Markdown summary — no preamble, no explanation, no code fences.
- Keep it a clean digest: short headings, bullet lists, **bold** for emphasis.
- Preserve the existing factual content unless the instruction asks to change it. Never invent chat content that isn't already in the summary.
- Reply in the SAME language as the existing summary.`;

export function editDiscordDigestUser(args: {
  current: string;
  instruction: string;
}): string {
  return [
    'Current summary:',
    '',
    args.current || '(empty)',
    '',
    '---',
    `Instruction: ${args.instruction}`,
    '',
    'Return the full revised summary in Markdown.',
  ].join('\n');
}
