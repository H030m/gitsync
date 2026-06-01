# Quality Guidelines (Flutter)

> The binding rules are in [`docs/AI_AGENT_RULES.md`](../../../docs/AI_AGENT_RULES.md) (esp. §3–§4).
> This is the frontend-specific checklist.

---

## Required patterns

- MVVM 5-layer boundaries hold (View → ViewModel → Repository → Firestore).
- `Consumer<VM>` in `build()`; `Provider.of<VM>(ctx, listen:false)` in callbacks.
- Navigation via `NavigationService`, never raw `context.go` / `Navigator.push`.
- `if (mounted)` before every post-`await` `BuildContext` use.
- Every `StreamSubscription` cancelled in `dispose()`.
- Repository writes carry `.timeout(const Duration(seconds: 10))`.
- Colors/text via `Theme.of(ctx).colorScheme` / `.textTheme` — no hardcoded colors.
- New repository/service methods are added to the Fake implementation too.

---

## Forbidden

- `print()` left in code; commented-out code; stray `TODO:` / `FIXME:` (unless asked).
- View importing `cloud_firestore` or `repositories/*`.
- ViewModel importing `material.dart` or holding `BuildContext`.
- New dependencies without asking. Specifically banned (course stack):
  **Riverpod / Bloc / GetX** (use `provider`), **auto_route** (use `go_router`),
  **dio** (use `cloud_functions` callables), **freezed / json_serializable** (hand-write maps).
  Allowed when no built-in fits: `fl_chart` / `graphic` for charts (ask first).
- Over-engineering: no abstractions "for the future", no wrappers for one-time <10-line logic.

---

## 🚫 The AI never runs these (user does — `AI_AGENT_RULES.md §R1/§R2/§R3`)

- `git commit` / `git push` / any history-writing git.
- `flutter pub add` / editing `pubspec.yaml` deps without asking.
- `firebase deploy`. Dev uses fake mode or `firebase emulators:start`.

---

## Verify before saying "done" (`AI_AGENT_RULES.md §4`)

- `flutter analyze` → 0 error / 0 warning (run it — the one info `use_null_aware_elements` is expected).
- Ran the golden path in fake mode (`flutter run`, default `BACKEND=fake`).
- Report with the 5-field format: ✅做了 / 📁動了 / ⚠️沒做 / 🧪驗證 / 💬建議 commit message
  (English, imperative; AI generates the string only, never runs `git commit`).
- Wrote a journal entry under `docs/journal/<you>.md` and updated `_index.md`. See the
  [shared quality bar](../guides/index.md).

## Testing

No broad widget-test suite yet (MVP). Minimum bar: `flutter analyze` clean + manual golden-path
run in fake mode. State clearly what was not verified (e.g. Android, live Firestore).
