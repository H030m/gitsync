# fix(askrepo-prompt): forbid inline commit SHAs in Ask GitSync answers

## Goal

Stop the Ask GitSync agent from quoting raw commit SHAs in its prose
answers (e.g. `(Commit SHA: 39c241925909b216377af5d1bf21d150970a39ed)`).
The source-panel cards below the answer already display the commit
with its author / date / short SHA — the inline citation is
redundant and visually noisy. User reported this with screenshots
showing every commit annotated with its full 40-char SHA.

## Root cause (diagnosed 2026-06-16)

`functions/src/prompts/askRepo.ts` already has a "Source panels"
section that tells the model:

> "So write a SHORT prose summary and let the panels display the
> commits — do NOT paste a list of commit shas / messages in your
> answer text."

The model reads this as "no LIST of SHAs" and slips them in as
parenthetical CITATIONS instead (`(Commit SHA: 39c2...)`). The
existing rule is too narrow — it bans "lists" but not inline
parentheticals.

## Decisions (locked 2026-06-16)

* **Single-file prompt strengthening.** Replace the existing "Source
  panels" sentence with an explicit, comprehensive prohibition that
  covers:
  * lists of SHAs (already covered)
  * inline SHAs in prose
  * parenthetical SHA citations (`(Commit SHA: ...)`)
  * shortened SHAs (the first 7-8 chars)
  * any commit hash-like 40-hex or short 7-hex string
* **Keep the section header "Source panels".** Other adjacent
  guidance ("write a SHORT prose summary", "let the panels display
  the commits") stays intact and reinforces the new rule.
* **Concrete wording locked**, given the model follows explicit-with-
  example rules more reliably than abstract ones:

  > Source panels:
  > - The commits and Discord snippets you retrieve are AUTOMATICALLY
  >   shown to the user as cards in source panels below your answer
  >   (one panel per window you built). Write a SHORT prose summary
  >   and let the panels display the commits.
  > - **NEVER write commit SHAs in your answer text.** Not as a list,
  >   not inline, not in parentheses, not as citations, not shortened.
  >   No `Commit SHA: 39c241925909…`, no `(commit 39c2419)`, no
  >   `commit 39c2419`. Refer to commits by what they DID (e.g. "the
  >   sign-up + login commit") — the source panel below carries the
  >   SHA, author, and date already. The same applies to Discord
  >   message IDs.

* **Single surface (`askRepo.ts`).** Other flows that read commits
  (`dailyBriefChat`, `discordChat`) use a different output shape
  and have not been reported with this issue. If the same problem
  shows up there, the equivalent one-line rule can be promoted to
  `prompts/analysisStyle.ts` (`COMMIT_ANALYSIS_RULES`) — separate task.

## Requirements

* Edit `functions/src/prompts/askRepo.ts` only.
* Replace the existing single-bullet "Source panels" block with the
  two-bullet block above.
* Keep wording terse — explicit negatives with one concrete example
  per banned form (per OpenAI's own prompt-rule guidance).
* No edits to `analysisStyle.ts`, `baseSystem.ts`, the flow code,
  the schema, or anything else.
* No frontend / `lib/` change.

## Acceptance Criteria

* [ ] `functions/src/prompts/askRepo.ts` contains the strengthened
      "Source panels" block exactly as locked above.
* [ ] `cd functions && npm run typecheck` clean.
* [ ] `cd functions && npm run lint` clean.
* [ ] `cd functions && npm test` — full suite green.
* [ ] Smoke (deferred to user): after `firebase deploy --only
      functions:askRepo` (or its callable equivalent), ask a question
      that surfaces multiple commits; the answer text should NOT
      contain `Commit SHA:`, `(commit `, or any 7-char or 40-char hex
      string referring to a commit.

## Definition of Done

* AC items pass.
* Single commit on develop.

## Out of Scope

* Promoting the rule to `COMMIT_ANALYSIS_RULES` for other flows. If
  the same issue surfaces in daily-brief or discord-chat output,
  separate task.
* Adding a server-side post-LLM regex stripper as a hard guarantee.
  The prompt-only fix is the right starting point; if the model
  slips, a regex pass can be added later — same pattern as the
  earlier Discord-username prompt fix.
* Banning short SHA references inside CODE blocks or quoted commit
  messages. Out of scope; the user's complaint is the agent's own
  prose annotations.

## Technical Notes

* The model is `gpt-4o-mini` (other callsites already use it; the
  Ask GitSync flow also reads `MODELS.fast` based on existing code).
  Mini-class models follow explicit-with-example rules more reliably
  than abstract ones — hence the concrete `Commit SHA: 39c2419...`
  example in the new rule.
* The base prompt (`baseSystem.ts`) is unchanged; agent-specific rules
  live in `askRepoBody`.
* No tests assert prompt content; the relevant flow tests stub the
  OpenAI client, so test signal is "didn't break the build".
