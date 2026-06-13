# Replace shell page-swap with CustomTransitionPage at GoRouter level

## Status

**Queued / planning-only**. Triggered manually when you're ready to
re-introduce the directional slide between bottom-nav tabs. The previous
shell-level `AnimatedSwitcher` attempt was reverted in task
`06-13-revert-animatedswitcher-bottom-nav-swap-globalkey-duplication-crash`
because keeping both routed subtrees alive simultaneously caused
`Duplicate GlobalKey` crashes.

## Goal

Re-introduce the bottom-nav directional slide animation the *correct* way:
per-route transitions at the GoRouter layer (`CustomTransitionPage`), so
each route owns its own widget tree and there are no overlapping GlobalKeys.

## Why this architecture (the why behind the rewrite)

GoRouter's `ShellRoute` shares a shell widget but mounts each child route
as a separate `Page`. If each tab's route declares a `pageBuilder` that
returns a `CustomTransitionPage` with our directional slide, GoRouter's
navigator handles the in/out animation between routes. The outgoing route
is a different Navigator entry, not a sibling KeyedSubtree in the shell —
so a `GlobalObjectKey` inside one route's tree never collides with the
same key in the next route.

## Design (sketch — to be locked in brainstorm)

* Refactor `lib/router/app_router.dart` route definitions for the four
  shell-mounted tabs (whatever the four `_NavItem` segments resolve to —
  inspect `repo_shell.dart`: probably `tasks`, `daily`, `stats`, `settings`).
* Replace each `GoRoute(builder: ...)` with `GoRoute(pageBuilder: (ctx,
  state) => CustomTransitionPage(child: <Page>(), transitionsBuilder: ...))`.
* Centralize the transition builder so all four routes share it — e.g.
  `lib/router/shell_transitions.dart` exporting a `sharedAxisSlide`
  function that returns the `(child, animation, secondaryAnimation, child)`
  builder.
* Animation: same shared-axis horizontal slide + fade design as the
  reverted attempt — `Offset(±0.06, 0)` enter/exit, `AppMotion.nav`
  duration, `AppMotion.emphasized` curve. **Use `secondaryAnimation` for
  the outgoing direction** — GoRouter/Navigator gives us both, so we
  don't have to detect direction from `animation.status` (which was the
  source of the original off-center bug in this iteration's history).
* Direction: GoRouter doesn't expose "previous index" directly. Easiest:
  derive direction from the route order (compare the new route's nav
  index against the old route's nav index via a `RouteObserver`, OR
  read `state.extra` set by the bottom-nav onTap). The bottom-nav onTap
  approach is cleaner — store the *intended* direction in
  `Routemaster`-style extra data when calling `context.go(...)` and
  the transition builder reads it via `state.extra`.

## Open questions (for brainstorm)

* Should the slide be horizontal only (matches the indicator's motion) or
  shared-axis (horizontal slide + cross-fade) per Material 3 navigation
  pattern? — Recommend shared-axis (matches what we reverted).
* Direction signal — `state.extra` carrying an intent, or a `RouteObserver`
  tracking the previous index? — Recommend `state.extra` for simplicity.
* What about back-gesture / browser-back? `secondaryAnimation` handles
  reverse direction automatically once we wire it up.
* Are there other GoRouter routes (non-shell, e.g. task-detail push) that
  should also get a CustomTransitionPage, or is this scoped to the four
  shell tabs only? — Recommend shell tabs only; task-detail keeps
  platform default until a separate task asks.

## Out of scope

* Hero transitions (e.g. kanban card → task detail). Separate task.
* The non-shell routes' transitions.
* Re-introducing any shell-level `AnimatedSwitcher` — that pattern is
  forbidden here. The route-level approach is the only architecture that
  avoids the GlobalKey crash.

## Pickup notes

When you're ready to run this task:

```bash
python ./.trellis/scripts/task.py start \
  .trellis/tasks/06-13-replace-shell-page-swap-with-customtransitionpage-at-gorouter-level
```

…then load `trellis-brainstorm` to converge the open questions, curate
jsonl, and dispatch `trellis-implement`.
