# perf: switch breakdownTask LLM to gpt-4o-mini for ~5× speedup

## Goal

Cut the user-visible wait time for the AI task breakdown by roughly
5× by routing its LLM calls through `gpt-4o-mini` (`MODELS.fast`)
instead of full `gpt-4o` (`MODELS.reasoning`). Other flows
(daily brief, explain commit, assign task, etc.) keep `gpt-4o`
unchanged.

## Root cause (diagnosed 2026-06-15)

`functions/src/flows/breakdownTask.ts` makes its OpenAI calls with
`model: MODELS.reasoning` (= `gpt-4o`) at three sites:

* line 196 — first-pass `openai.beta.chat.completions.parse` (empty
  repo path, structured output).
* line 227 — first-pass cycle re-prompt (same shape).
* line 403 — incremental agentic loop's `openai.chat.completions.create`
  (runs up to `MAX_ROUNDS = 5` times per breakdown).

`gpt-4o-mini` is roughly 5–10× faster than `gpt-4o` at the same prompt
length and supports both structured-output parsing
(`beta.chat.completions.parse`) and tool calls in the same way.

## Decisions (locked 2026-06-15)

* **Swap `MODELS.reasoning` → `MODELS.fast` at all 3 callsites in
  `functions/src/flows/breakdownTask.ts`.**
* **Keep `lib/config.ts` (`functions/src/config.ts`)
  `MODELS.reasoning` unchanged.** Other flows that genuinely benefit
  from `gpt-4o`'s quality (explain commit, daily brief, assign task)
  keep their current model.
* **No prompt change, no `MAX_ROUNDS` tuning, no
  `parallel_tool_calls: false`, no `readRepoPlanningDocs` truncation
  in this PR.** Those were ranked separately in the earlier
  scoping; this task is the single-line swap that ships first.
* If quality regresses noticeably in the wild, the reversal is a
  one-line change and can ship hot.

## Requirements

* `functions/src/flows/breakdownTask.ts`: 3 occurrences of
  `model: MODELS.reasoning` → `model: MODELS.fast`.
* No other file touched in `functions/`.
* No prompt, schema, tool, retry, or control-flow change.
* No frontend / `lib/` change.
* No `pubspec.yaml` / `package.json` change.

## Acceptance Criteria

* [ ] `grep -n "MODELS.reasoning" functions/src/flows/breakdownTask.ts`
      returns **zero** matches after the change.
* [ ] `grep -n "MODELS.fast" functions/src/flows/breakdownTask.ts`
      returns **exactly three** matches.
* [ ] `MODELS.reasoning` is still referenced by other flows
      (`onCommitCreated`, `dailyBriefChat`, `summarizeAuthorWork`,
      etc.) — verify by a repo-wide grep that the other flows are
      unchanged.
* [ ] `cd functions && npm run typecheck` clean.
* [ ] `cd functions && npm run lint` clean.
* [ ] `cd functions && npm test` — full suite green (the breakdown
      tests stub OpenAI; the model name change is invisible to them).

## Definition of Done

* AC items pass.
* Single commit on develop.

## Out of Scope (explicit)

* **Lowering `MAX_ROUNDS`** (the 5→3 win from the scoping report) —
  separate task if the model swap alone doesn't satisfy.
* **`parallel_tool_calls: false`** — separate task.
* **`readRepoPlanningDocs` size cap** — separate task.
* **Deterministic cycle-break fallback** — separate task.
* **UI progress signal** — separate frontend task; unrelated to the
  LLM call itself.
* **Changing `MODELS.reasoning` in `config.ts`** — global change
  would affect unrelated flows. Surgical per-site swap is the right
  scope.

## Technical Notes

* `gpt-4o-mini` supports `response_format: zodResponseFormat(...)`
  via `beta.chat.completions.parse` — verified by OpenAI's docs and
  by the same project's `onCommitCreated.ts` which already uses
  `MODELS.fast` for one-line summaries.
* `gpt-4o-mini` supports `tools` + `tool_choice: 'auto'` for the
  incremental loop; no schema/tool change is needed.
* If, after deploying, the breakdown quality regresses (e.g. cycles
  twice in succession, or trivial/incoherent subtasks), the
  individual callsite can be reverted to `MODELS.reasoning` while
  the rest stay on `MODELS.fast` — locality is preserved by keeping
  the swap inside this one file.
* `MODELS.reasoning` remains used by `onCommitCreated`,
  `dailyBriefChat`, `summarizeAuthorWork`, `summarizeDay`, and the
  triage agent's `triagePr` — none of those change.
