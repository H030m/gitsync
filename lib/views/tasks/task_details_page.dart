import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/tasks_board_vm.dart';

// TaskDetailsPage — title + description + handoff doc + dependencies.
// TODO: implement per prototype `tasks/TaskDetails.tsx`.
class TaskDetailsPage extends StatelessWidget {
  const TaskDetailsPage({
    super.key,
    required this.repoId,
    required this.taskId,
  });

  final String repoId;
  final String taskId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task details')),
      body: Consumer<TasksBoardViewModel>(
        builder: (ctx, vm, _) {
          final task = vm.tasks.firstWhere(
            (t) => t.id == taskId,
            orElse: () => Task(id: taskId, title: '(deleted)', createdBy: ''),
          );
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;
          final (chipBg, chipFg) = switch (task.status) {
            TaskStatus.todo => (scheme.surfaceContainerHighest, scheme.onSurface),
            TaskStatus.inProgress => (scheme.primaryContainer, scheme.onPrimaryContainer),
            TaskStatus.done => (scheme.secondaryContainer, scheme.onSecondaryContainer),
          };
          return ListView(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            children: [
              Text(
                task.title,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppDimens.spacingMd),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppDimens.spacingMd,
                  vertical: AppDimens.spacingSm - 2,
                ),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(AppDimens.radiusLg),
                ),
                child: Text(
                  task.status.wire,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: chipFg, fontWeight: FontWeight.w700),
                ),
              ),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle('Description'),
                const SizedBox(height: AppDimens.spacingSm),
                Text(task.description, style: theme.textTheme.bodyMedium),
              ],
              if (task.handoffDoc != null) ...[
                const SizedBox(height: AppDimens.spacingLg),
                _SectionTitle('Handoff'),
                const SizedBox(height: AppDimens.spacingSm),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(AppDimens.spacingMd),
                    child: Text(task.handoffDoc!, style: theme.textTheme.bodyMedium),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// Small uppercase label that heads a section of the task detail view.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
    );
  }
}
