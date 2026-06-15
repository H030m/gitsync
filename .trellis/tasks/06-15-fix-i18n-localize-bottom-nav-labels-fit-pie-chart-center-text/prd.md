# fix(i18n): localize bottom-nav labels + fit pie-chart center text

## Goal

Two English-mode UI bugs surfaced by the i18n switchover
(`5b7e562`). Fix both:

1. **Bottom-nav labels stay in Chinese in English mode.**
   `repo_shell.dart` hardcodes `'任務'`, `'每日彙整'`, `'統計'`, `'設定'`
   in a `static const _items` list that never reads `context.l10n`.
2. **Pie-chart center text overflows** the inner circle in English
   mode. The chart at `stats_view_page.dart` has
   `centerSpaceRadius: 28` (Ø ≈ 56 px) and the Column inside the
   Stack renders `s.contributionTab` ("Contribution") at
   `labelMedium`. The English word is much wider than the
   Chinese `'貢獻度'`, so it punches through the pie ring.

## Decisions (locked 2026-06-15)

### Bottom-nav i18n

* **Add 4 new keys to `lib/l10n/app_strings.dart`**, one per tab:
  * `navTasks` → `('Tasks', '任務')`
  * `navDaily` → `('Daily', '每日彙整')`
  * `navStats` → `('Stats', '統計')`
  * `navSettings` → `('Settings', '設定')`

  Naming: `nav*` prefix to distinguish from `contributionBasisTask`
  (which exists for a different surface and reads "Task" /
  "任務" — semantic context is different and re-using it would
  couple two unrelated UI areas).

* **`_items` is no longer `static const`.** Build it inside
  `build()` once per frame (cheap — 4 records). The list of items
  is small and stable; turning the `_NavItem` allocations into a
  per-build cost is negligible compared to readability.

* The icons + segments are unchanged.

### Pie-chart center text fitting

* **Constrain** the inner Column to a `SizedBox` whose width matches
  the inner circle's diameter minus a small padding margin —
  `width: 52` (centerSpaceRadius 28 → Ø 56, minus 2 px each side).
* **Wrap** each Text in `FittedBox(fit: BoxFit.scaleDown)` so the
  text auto-shrinks if it would overflow. `scaleDown` only shrinks;
  it never enlarges small Chinese strings, so the existing zh layout
  is preserved.
* **Keep both lines** (the `s.contributionTab` heading and the
  `s.pieChart` subtitle) — the user asked for fitting, not removal.
* No font-size override on the Text styles. FittedBox handles the
  shrinking; the styles stay theme-tokenised.

### Out of scope

* Reorganising AppStrings into separate locale files. Single-file
  `_(en, zh)` helper is the established convention.
* Adjusting the chart's `centerSpaceRadius` or pie ring thickness.
  Layout-shape changes risk a different look across themes; the
  text-fit fix is the right scope.
* Auditing other static-const widget lists for the same Chinese
  hardcoding. None obvious from inspection; if more surface
  Chinese-only text after this fix, separate task.
* The 3 pre-existing test failures (the `_SpyFunctions.breakdownTask`
  signature drift). Different cause; separate fix.

## Requirements

* `lib/l10n/app_strings.dart` gains exactly 4 new getters
  (`navTasks`, `navDaily`, `navStats`, `navSettings`), grouped with
  related navigation/labelling keys.
* `lib/views/shell/repo_shell.dart`:
  * `_items` rebuilt inside `build()` via `_buildNavItems(s)` (or
    similar local helper) reading from `context.l10n`.
  * Static const list removed or kept only as a list of structural
    metadata (icon + segment) with labels filled in at build time —
    pick whichever stays cleanest.
* `lib/views/stats/stats_view_page.dart`:
  * Lines 178–199: the Column is wrapped in
    `SizedBox(width: 52, child: Column(...))`.
  * Each Text inside the Column is wrapped in
    `FittedBox(fit: BoxFit.scaleDown)`.
  * No other change to the contribution pie layout.

## Acceptance Criteria

* [ ] English-mode run (`Settings → Language → English`): bottom-nav
      shows `Tasks`, `Daily`, `Stats`, `Settings`.
* [ ] zh-Hant run: bottom-nav shows `任務`, `每日彙整`, `統計`, `設定`
      (no regression).
* [ ] Contribution pie chart in English mode: "Contribution" + the
      `pieChart` subtitle visibly fit inside the inner circle, no
      intersection with pie sections.
* [ ] zh-Hant pie chart: unchanged appearance.
* [ ] `flutter build web` — green.
* [ ] `flutter test` — same baseline as before this commit
      (current `+90 -3`; the 3 spy-signature failures are
      pre-existing and out of scope).

## Definition of Done

* AC items pass.
* Single commit on develop.
* `flutter analyze` skipped per project memory (CJK-path bug).
* No edits under `functions/`.

## Technical Notes

* `_NavItem` is a tiny holder (`icon`, `selectedIcon`, `label`,
  `segment`). Allocating four per build is sub-microsecond; we
  already do far heavier work per frame on this page.
* `FittedBox(fit: BoxFit.scaleDown)` is the textbook way to make
  text shrink-to-fit without harming shorter strings. It does not
  affect IntrinsicWidth measurement; pairing with `SizedBox(width:
  52)` ensures a hard ceiling that triggers the scale-down
  behaviour.
* The existing zh-Hant text styling depends on `labelMedium` and
  `labelSmall`; preserving them keeps the design tokens centralized.
