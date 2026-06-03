import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/task.dart';
import '../../theme/app_dimens.dart';
import '../../view_models/tasks_board_vm.dart';

/// TaskDetailsPage — card-based layout matching Figma prototype.
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
      appBar: AppBar(title: const Text('任務細節'), centerTitle: true),
      body: Consumer<TasksBoardViewModel>(
        builder: (ctx, vm, _) {
          final task = vm.tasks.firstWhere(
            (t) => t.id == taskId,
            orElse: () => Task(id: taskId, title: '(deleted)', createdBy: ''),
          );
          return ListView(
            padding: const EdgeInsets.all(AppDimens.spacingMd),
            children: [
              _AssigneeCard(task: task),
              const SizedBox(height: AppDimens.spacingSm),
              _TaskContentCard(task: task),
              if (task.handoffDoc != null) ...[
                const SizedBox(height: AppDimens.spacingSm),
                _HandoffCard(handoffDoc: task.handoffDoc!),
              ],
            ],
          );
        },
      ),
    );
  }
}

Color _cardBg(BuildContext context) {
  return Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF222630)
      : Theme.of(context).colorScheme.surface;
}

BoxShadow _subtleShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    color: isDark
        ? Colors.black.withValues(alpha: 0.2)
        : const Color(0xFF1565C0).withValues(alpha: 0.09),
    blurRadius: 3,
    offset: const Offset(0, 1),
  );
}

BoxShadow _strongShadow(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return BoxShadow(
    color: isDark
        ? Colors.black.withValues(alpha: 0.3)
        : const Color(0xFF1565C0).withValues(alpha: 0.14),
    blurRadius: 8,
    offset: const Offset(0, 2),
  );
}

// ---------------------------------------------------------------------------
// 1. Assignee card
// ---------------------------------------------------------------------------
class _AssigneeCard extends StatelessWidget {
  const _AssigneeCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final assignee = task.assigneeId;
    final hasAssignee = assignee != null && assignee.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        boxShadow: [_subtleShadow(context)],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: hasAssignee ? scheme.primary : scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: hasAssignee
                  ? Text(
                      assignee.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : Icon(Icons.person, size: 16, color: scheme.primary),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '認領者',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              hasAssignee
                  ? Text(
                      assignee,
                      style: const TextStyle(fontSize: 13),
                    )
                  : Container(
                      height: 8,
                      width: 80,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Task content card
// ---------------------------------------------------------------------------
class _TaskContentCard extends StatelessWidget {
  const _TaskContentCard({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        boxShadow: [_strongShadow(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.checklist, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '任務內容',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.surfaceContainerHighest),
          const SizedBox(height: 12),

          // Task title
          Text(
            task.title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),

          // Description
          if (task.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              ),
              child: Text(
                task.description,
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],

          // Acceptance criteria as subtasks
          if (task.acceptanceCriteria.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              '子任務',
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < task.acceptanceCriteria.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 4),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        task.acceptanceCriteria[i],
                        style: const TextStyle(fontSize: 12, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Handoff card
// ---------------------------------------------------------------------------
class _HandoffCard extends StatelessWidget {
  const _HandoffCard({required this.handoffDoc});
  final String handoffDoc;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppDimens.spacingMd),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        boxShadow: [_strongShadow(context)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with AI badge
          Row(
            children: [
              Icon(Icons.chat_bubble_outline, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                '交接內容',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome, size: 10, color: scheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      'AI 生成',
                      style: TextStyle(fontSize: 10, color: scheme.primary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.surfaceContainerHighest),
          const SizedBox(height: 12),

          // Notes with left accent bar
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    handoffDoc,
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
