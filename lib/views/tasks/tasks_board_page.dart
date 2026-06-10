import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../services/navigation.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/tasks_board_vm.dart';
import 'widgets/task_graph_tab.dart';

// TasksBoardPage — kanban + relation-graph tabs.
// TODO: implement drag-and-drop kanban + relation graph per prototype
// `tasks/TasksBoard.tsx`.
class TasksBoardPage extends StatelessWidget {
  const TasksBoardPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Tasks'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.view_kanban), text: 'Board'),
              Tab(icon: Icon(Icons.account_tree), text: 'Graph'),
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

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.vm});
  final TasksBoardViewModel vm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _Column(
              title: 'To do',
              tasks: vm.todo,
              accent: scheme.outline,
            ),
          ),
          Expanded(
            child: _Column(
              title: 'In progress',
              tasks: vm.inProgress,
              accent: scheme.primary,
            ),
          ),
          Expanded(
            child: _Column(
              title: 'Done',
              tasks: vm.done,
              accent: scheme.secondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.tasks,
    required this.accent,
  });
  final String title;
  final List<Task> tasks;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDimens.spacingSm + AppDimens.spacingXs,
            vertical: AppDimens.spacingSm,
          ),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppDimens.spacingSm),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _CountBadge(count: tasks.length, color: accent),
            ],
          ),
        ),
        Expanded(
          child: tasks.isEmpty
              ? Center(
                  child: Text(
                    '—',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: AppDimens.spacingLg),
                  itemCount: tasks.length,
                  itemBuilder: (ctx, i) {
                    final t = tasks[i];
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppDimens.spacingSm,
                        vertical: AppDimens.spacingXs,
                      ),
                      child: ListTile(
                        title: Text(
                          t.title,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: t.description.isEmpty
                            ? null
                            : Text(
                                t.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                        onTap: () => Provider.of<NavigationService>(ctx,
                                listen: false)
                            .goTaskDetails(
                                Provider.of<TasksBoardViewModel>(ctx,
                                        listen: false)
                                    .repoId,
                                t.id),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// Small pill showing the number of tasks in a board column.
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.spacingSm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
