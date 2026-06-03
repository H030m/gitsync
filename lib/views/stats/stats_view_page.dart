import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../theme/app_dimens.dart';
import '../../view_models/commits_vm.dart';
import '../../view_models/stats_vm.dart';
import '../../view_models/tasks_board_vm.dart';

// StatsViewPage — task status pie + commits-per-author bar chart.
// TODO: implement actual charts with `fl_chart` per prototype
// `stats/StatsView.tsx`.
class StatsViewPage extends StatelessWidget {
  const StatsViewPage({super.key, required this.repoId});
  final String repoId;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProxyProvider2<TasksBoardViewModel, CommitsViewModel,
        StatsViewModel>(
      create: (_) => StatsViewModel(),
      update: (_, tasks, commits, prev) =>
          (prev ?? StatsViewModel())..updateFromUpstream(tasks: tasks, commits: commits),
      child: Scaffold(
        appBar: AppBar(title: const Text('統計'), centerTitle: true),
        body: Consumer<StatsViewModel>(
          builder: (ctx, vm, _) {
            final scheme = Theme.of(ctx).colorScheme;
            final statusMax = vm.statusCounts.values.fold<int>(0, _max);
            final authorMax = vm.commitsPerAuthor.values.fold<int>(0, _max);
            return ListView(
              padding: const EdgeInsets.all(AppDimens.spacingMd),
              children: [
                _StatCard(
                  title: '任務狀態',
                  icon: Icons.task_alt_outlined,
                  child: Column(
                    children: [
                      for (final entry in vm.statusCounts.entries)
                        _BarRow(
                          label: entry.key.name,
                          value: entry.value,
                          max: statusMax,
                          color: scheme.primary,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppDimens.spacingMd),
                _StatCard(
                  title: '每人 commit 數',
                  icon: Icons.commit_outlined,
                  child: Column(
                    children: [
                      for (final entry in vm.commitsPerAuthor.entries)
                        _BarRow(
                          label: entry.key,
                          value: entry.value,
                          max: authorMax,
                          color: scheme.tertiary,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _max(int a, int b) => a > b ? a : b;
}

// Titled card wrapper for a stats section.
class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.icon, required this.child});
  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: AppDimens.spacingSm),
                Text(title,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: AppDimens.spacingMd),
            child,
          ],
        ),
      ),
    );
  }
}

// A label + proportional bar + count, used for both stats sections.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });
  final String label;
  final int value;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = max == 0 ? 0.0 : value / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppDimens.spacingXs + 2),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: AppDimens.spacingSm),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppDimens.radiusSm),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ),
          const SizedBox(width: AppDimens.spacingSm),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
