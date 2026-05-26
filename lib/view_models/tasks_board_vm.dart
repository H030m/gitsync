import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/task.dart';
import '../repositories/task_repo.dart';

// Streams every task in a repo (TasksBoardPage + TaskDetailsPage).
class TasksBoardViewModel with ChangeNotifier {
  TasksBoardViewModel({
    required String repoId,
    TaskRepository? taskRepository,
  })  : _repoId = repoId,
        _repo = taskRepository ?? TaskRepository() {
    _sub = _repo.streamTasks(_repoId).listen((tasks) {
      _tasks = tasks;
      _loading = false;
      notifyListeners();
    });
  }

  final String _repoId;
  final TaskRepository _repo;
  StreamSubscription<List<Task>>? _sub;

  List<Task> _tasks = [];
  List<Task> get tasks => _tasks;
  String get repoId => _repoId;

  bool _loading = true;
  bool get loading => _loading;

  // ---- Status groupings (consumed by the kanban board) -------------------

  List<Task> get todo =>
      _tasks.where((t) => t.status == TaskStatus.todo).toList();
  List<Task> get inProgress =>
      _tasks.where((t) => t.status == TaskStatus.inProgress).toList();
  List<Task> get done =>
      _tasks.where((t) => t.status == TaskStatus.done).toList();

  // ---- Mutations ---------------------------------------------------------

  Future<void> updateStatus(String taskId, TaskStatus status) async {
    await _repo.updateStatus(_repoId, taskId, status);
  }

  Future<void> assignTo(String taskId, String? assigneeId) async {
    await _repo.assignTo(_repoId, taskId, assigneeId);
  }

  Future<String> addTask(Task task) async {
    return _repo.addTask(_repoId, task);
  }

  Future<void> deleteTask(String taskId) async {
    await _repo.deleteTask(_repoId, taskId);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
