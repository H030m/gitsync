import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../services/navigation.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/tasks_board_vm.dart';
import 'widgets/task_graph_tab.dart';

// TasksBoardPage — kanban (看板) + dependency-graph (關聯圖) tabs.
// Faithful restyle of the prototype `tasks/TasksBoard.tsx`: a horizontally
// scrollable row of fixed-width columns (待辦 / 進行中 / 完成) with tonal
// headers, count chips, assignee-initial circles, and long-press drag-and-drop
// between columns. See task 06-06.
class TasksBoardPage extends StatelessWidget {
  const TasksBoardPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('任務'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '看板'),
              Tab(text: '關聯圖'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () =>
              Provider.of<NavigationService>(context, listen: false)
                  .goAddTodo(repoId),
          child: const Icon(Icons.add),
        ),
        body: Consumer<TasksBoardViewModel>(
          builder: (ctx, vm, _) {
            if (vm.loading) {
              return const Center(child: CircularProgressIndicator());
            }
            return TabBarView(
              children: [
                _BoardTab(vm: vm),
                TaskGraphTab(vm: vm),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Per-column visual tokens. Tints are derived from the active ColorScheme via an
// exhaustive switch on TaskStatus (no hardcoded hexes) so light + dark both read
// as a graded primary family: header background (tonal), accent (label + chip),
// and the column label.
class _ColumnTheme {
  const _ColumnTheme({
    required this.label,
    required this.tonal,
    required this.accent,
  });
  final String label;
  final Color tonal;
  final Color accent;

  static _ColumnTheme of(ColorScheme scheme, TaskStatus status) {
    return switch (status) {
      TaskStatus.todo => _ColumnTheme(
          label: '待辦',
          tonal: scheme.surfaceContainerHighest,
          accent: scheme.primary.withValues(alpha: 0.55),
        ),
      TaskStatus.inProgress => _ColumnTheme(
          label: '進行中',
          tonal: scheme.primaryContainer,
          accent: scheme.primary,
        ),
      TaskStatus.done => _ColumnTheme(
          label: '完成',
          tonal: scheme.secondaryContainer,
          accent: scheme.secondary,
        ),
    };
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.vm});
  final TasksBoardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final allEmpty = vm.tasks.isEmpty;
    if (allEmpty) return const _EmptyBoard();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSm + AppDimens.spacingXs,
        vertical: AppDimens.spacingSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BoardColumn(vm: vm, status: TaskStatus.todo, tasks: vm.todo),
          const SizedBox(width: AppDimens.spacingSm + 2),
          _BoardColumn(
              vm: vm, status: TaskStatus.inProgress, tasks: vm.inProgress),
          const SizedBox(width: AppDimens.spacingSm + 2),
          _BoardColumn(vm: vm, status: TaskStatus.done, tasks: vm.done),
        ],
      ),
    );
  }
}

// Centered card shown when every column is empty — mirrors the prototype copy.
class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingLg),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(AppDimens.spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                Text(
                  '您還未輸入專案架構',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurface),
                ),
                const SizedBox(height: AppDimens.spacingXs),
                Text(
                  '請點擊右下角 + 號來新增 TODOs',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// One fixed-width kanban column: a tonal header (label + count chip) over a
// secondary-background card list. The body is a DragTarget that accepts cards
// from other columns and writes the new status through the ViewModel.
class _BoardColumn extends StatefulWidget {
  const _BoardColumn({
    required this.vm,
    required this.status,
    required this.tasks,
  });

  final TasksBoardViewModel vm;
  final TaskStatus status;
  final List<Task> tasks;

  @override
  State<_BoardColumn> createState() => _BoardColumnState();
}

class _BoardColumnState extends State<_BoardColumn> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colTheme = _ColumnTheme.of(scheme, widget.status);

    return SizedBox(
      width: 150,
      child: DragTarget<Task>(
        onWillAcceptWithDetails: (details) =>
            details.data.status != widget.status,
        onAcceptWithDetails: (details) => _accept(details.data),
        builder: (context, candidate, rejected) {
          final hovering = candidate.isNotEmpty;
          return Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              border: Border.all(
                color: hovering ? colTheme.accent : Colors.transparent,
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tonal header: accent label + count chip.
                Container(
                  color: colTheme.tonal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimens.spacingSm + AppDimens.spacingXs,
                    vertical: AppDimens.spacingSm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          colTheme.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colTheme.accent,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _CountChip(
                        count: widget.tasks.length,
                        accent: colTheme.accent,
                      ),
                    ],
                  ),
                ),
                // Card list (secondary background), tinted while hovering.
                Container(
                  color: hovering
                      ? colTheme.accent.withValues(alpha: 0.08)
                      : Colors.transparent,
                  padding: const EdgeInsets.all(AppDimens.spacingSm),
                  constraints: const BoxConstraints(minHeight: 120),
                  child: widget.tasks.isEmpty
                      ? SizedBox(
                          height: 80,
                          child: Center(
                            child: Text(
                              '—',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final t in widget.tasks)
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppDimens.spacingSm,
                                ),
                                child: _TaskCard(
                                  vm: widget.vm,
                                  task: t,
                                  accent: colTheme.accent,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _accept(Task task) async {
    try {
      await widget.vm.updateStatus(task.id, widget.status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('更新狀態失敗：$e')),
        );
    }
  }
}

// Small pill showing the number of cards in a column: accent @ ~20% bg + accent
// text, per the prototype.
class _CountChip extends StatelessWidget {
  const _CountChip({required this.count, required this.accent});
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

// A draggable task card: rounded, elevated, title + an assignee-initial circle
// bottom-right. Long-press to drag between columns; tap to open TaskDetails.
class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.vm,
    required this.task,
    required this.accent,
  });

  final TasksBoardViewModel vm;
  final Task task;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final card = _CardBody(task: task, accent: accent);
    return LongPressDraggable<Task>(
      data: task,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.9,
          child: SizedBox(
            width: 134,
            child: _CardBody(task: task, accent: accent, elevated: true),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        onTap: () => Provider.of<NavigationService>(context, listen: false)
            .goTaskDetails(vm.repoId, task.id),
        child: card,
      ),
    );
  }
}

class _CardBody extends StatelessWidget {
  const _CardBody({
    required this.task,
    required this.accent,
    this.elevated = false,
  });

  final Task task;
  final Color accent;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingSm + 2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: elevated ? 0.22 : 0.08),
            blurRadius: elevated ? 10 : 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurface, height: 1.25),
          ),
          const SizedBox(height: AppDimens.spacingSm),
          Align(
            alignment: Alignment.centerRight,
            child: _AssigneeCircle(assigneeId: task.assigneeId, accent: accent),
          ),
        ],
      ),
    );
  }
}

// Bottom-right initial circle: accent-tinted with the assignee's first character
// when assigned, otherwise a plain grey circle (unassigned).
class _AssigneeCircle extends StatelessWidget {
  const _AssigneeCircle({required this.assigneeId, required this.accent});
  final String? assigneeId;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final id = assigneeId;
    if (id == null || id.isEmpty) {
      return Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
      );
    }
    final initial = id.substring(0, 1).toUpperCase();
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
