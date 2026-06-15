# fix(tests): add language param to _SpyFunctions.breakdownTask overrides

## Goal

Restore the test suite to a clean `+98 -0` baseline. Three test files
currently fail to compile (`+90 -3`) because two `FunctionsService`
test spies were written before `breakdownTask` grew the
`String? language` named parameter, and their overrides don't match
the abstract signature anymore.

## Root cause (diagnosed 2026-06-15)

`lib/services/functions_service.dart:49`:

```dart
Future<List<SubTask>> breakdownTask({
  required String repoId,
  required String goal,
  String? language,                    // ← added by an i18n commit
});
```

Two test spies still declare the old shape (no `language:` named param)
and therefore fail Dart's "named arguments must match" check:

* `test/repo_list_vm_test.dart:52` — `_SpyFunctions` (declares
  `breakdownTask`, body just throws `UnimplementedError`).
* `test/daily_discord_tab_test.dart:78` — `_SpyFunctions` (declares
  `breakdownTask`, body delegates to a `_fake.breakdownTask(...)`).

The third reported failure, `test/regenerate_locale_test.dart`, is
**collateral damage** from the suite-level compilation step — it passes
cleanly when run in isolation (`+4: All tests passed!`). Its
`_CapturingFunctionsService` already uses `noSuchMethod` as a fallback
and does NOT need a `breakdownTask` override. Once the two real
compile errors are gone, this file's transient suite-mode failure
should clear too.

`lib/services/fake/fake_functions_service.dart:44` already accepts
`String? language` (its implementation forwards it / ignores it),
so the daily-discord spy can pass `language: language` through with
no source change to the fake.

## Decisions (locked 2026-06-15)

* **`test/repo_list_vm_test.dart`** — add `String? language,` to the
  spy's `breakdownTask` signature. Body stays
  `throw UnimplementedError();` (untouched). No other edit.

* **`test/daily_discord_tab_test.dart`** — add `String? language,` to
  the spy's `breakdownTask` signature **and** pass it through to the
  delegated `_fake.breakdownTask(repoId: …, goal: …, language: language)`.
  No other edit.

* **No production-code change.** The fix is entirely test-side.

* **No spec or shared helper edit.** Two test files; the existing
  per-spy override pattern is fine.

## Requirements

* Two test files modified; one named param added per spy; one
  delegated call updated in the daily-discord spy.
* No edits under `lib/` or `functions/`.
* No new pubspec entries.

## Acceptance Criteria

* [ ] `flutter test` exits `+98 -0` (the three currently-failing
      files all pass).
* [ ] No new failures introduced — all currently-passing tests
      remain green.
* [ ] `flutter build web` — green.

## Definition of Done

* AC items pass.
* Single commit on develop.
* `flutter analyze` skipped per project memory (CJK-path bug).

## Out of Scope

* Refactoring the spies to use `mocktail` or another framework.
* Updating any other spy / fake / shim in the project (none other
  drift seen).
* Modifying the canonical `FunctionsService.breakdownTask` signature
  or the language-forwarding behaviour.

## Technical Notes

* Dart's "named arguments must match" check fires at compile time,
  which is why these files fail to LOAD (not at runtime) in the
  full suite — that's also why `regenerate_locale_test.dart`
  passes in isolation but gets blamed for "loading" failures in
  suite mode.
* The two-line nature of the fix doesn't earn a brainstorm beyond
  this PRD; the design is mechanical and locked.
