# fix(ui): task-graph legend matches node body color + clearer status palette

## Goal

In `任務/關聯圖` (Tasks → Graph tab), the status legend dot color doesn't
match what the user perceives as "the node's color", and the three
status colours (todo / in-progress / done) are hard to tell apart in the
default Material 3 light theme. Fix both.

## Root cause (diagnosed 2026-06-15)

`lib/views/tasks/widgets/task_graph_tab.dart` defines a shared palette:

```dart
(Color, Color, Color) _statusColors(ColorScheme scheme, TaskStatus status) {
  // returns (bg, fg, accent)
  // todo        → surfaceContainerHighest / onSurface / outline
  // inProgress  → primaryContainer        / onPrimaryContainer / primary
  // done        → secondaryContainer      / onSecondaryContainer / secondary
}
```

* **Node card body** (the large, visually dominant area) uses `bg`.
* **Node accent dot** (small dot inside the card, line 553) uses `accent`.
* **Legend dot** (line 479) ALSO uses `accent`.

So the legend dot color matches the *tiny accent dot inside the node*,
not the node body the user reads as "the colour". That's the mismatch
the user reported.

Secondary problem: `primaryContainer` and `secondaryContainer` in the
default Material 3 light theme are both soft pastels and very close in
chroma; even after the mismatch is fixed, users will struggle to tell
"in progress" apart from "done".

## Decisions (locked 2026-06-15)

* **Legend mirrors node body, not accent.** Legend dot uses
  `_statusColors(scheme, status).$1` (the `bg`). This is what the user
  actually sees and reads as "the status colour".
* **Palette change for higher distinguishability**, while staying
  fully theme-aware (no hardcoded `Colors.green`-style picks):
  * todo        → `surfaceContainerHighest` (neutral grey — unchanged)
  * inProgress  → `primaryContainer` (primary hue — unchanged)
  * done        → **`tertiaryContainer`** (different hue family —
    was `secondaryContainer`)
  * Accent (the dot inside the node card + edge tints if any) shifts
    in lockstep:
    * todo        → `outline`
    * inProgress  → `primary`
    * done        → **`tertiary`** (was `secondary`)
  * Foreground text colour:
    * todo        → `onSurface`
    * inProgress  → `onPrimaryContainer`
    * done        → **`onTertiaryContainer`** (was `onSecondaryContainer`)
  * Rationale: `tertiary*` slots in Material 3 are defined to be a
    different hue family from `primary`/`secondary`, intentionally for
    cases where the team needs a visually distinct third role. That's
    exactly what we want here.
* **No theme-file edits.** The default Material 3 `tertiary` derived
  from the seed colour is enough; we don't need to override the
  `tertiary` slot in `lib/theme/app_theme.dart`.
* **No other UI surfaces touched.** The kanban board's status colors
  (`tasks_board_page.dart`) live in their own helper and use a
  different convention; if any contrast complaint shows up there
  later, it earns its own task.

## Requirements

* Update `_statusColors` in
  `lib/views/tasks/widgets/task_graph_tab.dart` so `done` returns the
  `tertiary`-family tokens listed above.
* Update `_StatusLegend.build` so the dot uses `.$1` (bg) instead of
  `.$3` (accent). Same dot size (8×8), same border / margin / label.
* Optional polish: add a thin 0.5 px outline to each legend dot so the
  todo neutral colour reads against the legend's own
  `surfaceContainerHigh` background.
* No other file edits.
* No new pubspec entries.
* No widget-test changes (no test currently covers legend colours).

## Acceptance Criteria

* [ ] In light theme on Chrome / Path B, the three legend dots match
      the three node card body colours one-to-one (same hue, same
      tone).
* [ ] `todo`, `inProgress`, `done` are visibly distinct in both light
      and dark Material 3 default themes — no two of them feel "the
      same colour at a glance".
* [ ] The accent dot inside each node card stays consistent (same
      hue family as the node body).
* [ ] `flutter test` — `+98 -0` baseline unchanged.
* [ ] `flutter build web` — green.

## Definition of Done

* AC items pass.
* Single commit on develop.
* `flutter analyze` skipped per project memory.

## Out of Scope

* Editing the theme seed / overriding `tertiary` colours in
  `app_theme.dart` — Material 3's default derivation is enough.
* Auditing other status-coloured surfaces (kanban board, daily
  cards). Different surfaces, different code paths.
* Adding a colour-blind safe mode (the tertiary palette change
  already helps; an explicit pattern/icon overlay would be a
  separate, larger task).
* Dark-mode-only tuning. Material 3's tonal palette handles
  dark mode automatically and the legend/node mirroring works in
  both.

## Technical Notes

* The accent dot is also referenced by edge tinting in the painter
  (search for `.color = scheme.primary` around line 257 — that's
  separate from the per-node accent and stays as `scheme.primary`
  because edges are uniform, not per-status).
* `_statusLabel` already shares between node + legend; the same
  shared-source-of-truth pattern is preserved by the fix.
* Material 3 `onTertiaryContainer` provides sufficient contrast
  against `tertiaryContainer` per the WCAG AA threshold; no
  contrast-check fixture is needed.
