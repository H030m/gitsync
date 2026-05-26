import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
        appBar: AppBar(title: const Text('Stats')),
        body: Consumer<StatsViewModel>(
          builder: (ctx, vm, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Task status',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final entry in vm.statusCounts.entries)
                Text('${entry.key.name}: ${entry.value}'),
              const SizedBox(height: 24),
              Text('Commits per author',
                  style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final entry in vm.commitsPerAuthor.entries)
                Text('${entry.key}: ${entry.value}'),
            ],
          ),
        ),
      ),
    );
  }
}
