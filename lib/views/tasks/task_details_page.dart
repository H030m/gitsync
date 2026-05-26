import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(task.title, style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Status: ${task.status.wire}'),
              if (task.description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(task.description),
              ],
              if (task.handoffDoc != null) ...[
                const SizedBox(height: 24),
                Text('Handoff', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(task.handoffDoc!),
              ],
            ],
          );
        },
      ),
    );
  }
}
