import 'package:flutter/foundation.dart';

import '../models/task.dart';
import 'commits_vm.dart';
import 'tasks_board_vm.dart';

// Derived statistics view (StatsViewPage) built from TasksBoardViewModel and
// CommitsViewModel. Plug both in via ChangeNotifierProxyProvider2 in main.dart
// or the route layer.
class StatsViewModel with ChangeNotifier {
  TasksBoardViewModel? _tasksVm;
  CommitsViewModel? _commitsVm;

  Map<TaskStatus, int> _statusCounts = const {};
  Map<TaskStatus, int> get statusCounts => _statusCounts;

  Map<String, int> _commitsPerAuthor = const {};
  Map<String, int> get commitsPerAuthor => _commitsPerAuthor;

  // Receives upstream updates from ChangeNotifierProxyProvider2.
  void updateFromUpstream({
    required TasksBoardViewModel tasks,
    required CommitsViewModel commits,
  }) {
    _tasksVm = tasks;
    _commitsVm = commits;
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final tasks = _tasksVm?.tasks ?? const <Task>[];
    final counts = <TaskStatus, int>{
      TaskStatus.todo: 0,
      TaskStatus.inProgress: 0,
      TaskStatus.done: 0,
    };
    for (final t in tasks) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    _statusCounts = counts;

    final perAuthor = <String, int>{};
    for (final c in _commitsVm?.commits ?? const []) {
      perAuthor.update(c.author.login, (v) => v + 1, ifAbsent: () => 1);
    }
    _commitsPerAuthor = perAuthor;
  }
}
