# Component (Widget / View) Guidelines

> Flutter has Widgets, not React components. "Views" = full-screen page Widgets in `lib/views/`;
> reusable pieces go in `lib/widgets/` (create when first needed).
> Source: [`COURSE_METHODS.md`](../../../docs/COURSE_METHODS.md), [`AI_AGENT_RULES.md §3`](../../../docs/AI_AGENT_RULES.md).

---

## View layer rules

- A page is a `XxxPage` Widget (usually `StatefulWidget` when it has form/animation state).
- Read state with `Consumer<VM>` in `build()`; read one-shot (no rebuild) with
  `Provider.of<VM>(ctx, listen: false)` inside callbacks.
- **Never** import `cloud_firestore` or `repositories/*` in a View. Go through the ViewModel.
- **Navigation** goes through `NavigationService` (`Provider.of<NavigationService>(ctx,
  listen:false).goTasks(repoId)`), never raw `context.go(...)` or `Navigator.push` — and never
  mix GoRouter with Navigator 1.0.

---

## Async + BuildContext

Every `BuildContext` use after an `await` must be guarded by `if (mounted)`:

```dart
try {
  await viewModel.addTask(newTask);
  if (mounted) {
    Provider.of<NavigationService>(context, listen: false).pop(context);
  }
} on TimeoutException catch (e) {
  if (mounted) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Operation timed out: ${e.message}')));
  }
}
```

User-facing error handling (snackbars, dialogs) belongs **in the View** — not swallowed in the
ViewModel. The Repository adds a `.timeout(...)` and does **not** catch (see
[`hook-guidelines.md`](./hook-guidelines.md)).

---

## Styling / Theme

- **Never hardcode color strings.** Use `Theme.of(ctx).colorScheme.X` and
  `Theme.of(ctx).textTheme.X`. Brand colors live in `lib/theme/app_colors.dart` and are wired via
  `ColorScheme.fromSeed` in `app_theme.dart` (light seed `#1565C0`, dark accent `#FAB28E`).
- Spacing/radius tokens per [`ARCHITECTURE.md §8.2`](../../../docs/ARCHITECTURE.md) are codified in
  `lib/theme/app_dimens.dart` (`AppDimens.radiusSm/Md/Lg`, `spacingXs/Sm/Md/Lg`). **Use these
  instead of magic numbers** for padding/radius.
- Component look (Card, AppBar, FilledButton, SegmentedButton, inputs, ListTile, Divider, TabBar,
  FAB, SnackBar) is centralized in the `_themeFrom(...)` factory in `app_theme.dart`. **Polish
  app-wide by editing that one factory**, not per-page — both light and dark inherit it.
- Reuse `EmptyState(icon, title, message)` from `lib/widgets/empty_state.dart` for "nothing here
  yet" placeholders instead of a bare centered `Text`.
- Theme mode: `ThemeModeNotifier` defaults to `ThemeMode.system` with **no persistence**
  (resets on reload — intentional). Settings exposes a 3-way System/Light/Dark `SegmentedButton`,
  **not** a binary switch (a switch reading `mode == dark` contradicts the system default).

---

## Forms

```dart
final _formKey = GlobalKey<FormState>();
// ...
Future<void> _submit() async {
  if (!_formKey.currentState!.validate()) return;
  _formKey.currentState!.save();
  // call viewModel.addX()
}
```

---

## Graph / DAG visualization (graphview)

Task dependency graphs render with the **`graphview`** package + a layered Sugiyama
layout (`lib/views/tasks/widgets/task_graph_tab.dart`). Conventions learned:

- Use the **plain `GraphView(...)` constructor wrapped in your own
  `InteractiveViewer(constrained: false, ...)`** for pan/zoom. Do **not** use
  `GraphView.builder` — it injects its *own* internal `InteractiveViewer` (fixed
  `boundaryMargin: infinity`, `minScale: 0.01`), so combining it with a custom one
  double-nests them and you lose control of the zoom bounds.
- `addNode(Node.Id(id))` for **every** task first, then `addEdge` — otherwise
  dependency-less tasks vanish (edges alone only create their endpoints).
- Edge direction = **prerequisite → dependent** (`addEdge(Node.Id(depId), Node.Id(taskId))`).
  Guard against dangling edges: skip a `depId` not present in the current task set.
- `Node.Id(x)` stores `key = ValueKey(x)`; read it back in the builder via
  `node.key!.value`. Map id → model object for the node widget.
- Node colors come from `Theme.of(ctx).colorScheme` keyed on the status enum with an
  exhaustive `switch` (no `default`, so a new status is a compile error), per Styling above.

---

## Scope discipline (`AI_AGENT_RULES.md §3.2`)

Implement only what was asked. Don't add confirmation dialogs, undo snackbars, analytics, extra
comments, or refactors that weren't requested. If you think one is warranted, ask in the final
message — don't add it silently.

---

## Common mistakes

- Importing a Repository directly into a View.
- Using `context` after `await` without `if (mounted)`.
- Hardcoding `Color(0xFF...)` instead of `colorScheme`.
- Forgetting to add a new repository method to the Fake implementation (breaks `BACKEND=fake`).
