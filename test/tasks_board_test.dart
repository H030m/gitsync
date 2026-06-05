import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:gitsync/models/task.dart';
import 'package:gitsync/repositories/task_repo.dart';
import 'package:gitsync/services/navigation.dart';
import 'package:gitsync/view_models/tasks_board_vm.dart';
import 'package:gitsync/views/tasks/tasks_board_page.dart';

// In-test fake so each case gets an isolated, fully-controlled task list (the
// app's FakeTaskRepository is a shared singleton seeded with demo data). Only
// the methods the board exercises are implemented; the rest throw.
class _StubTaskRepo implements TaskRepository {
  _StubTaskRepo(List<Task> seed) : _tasks = List.of(seed);

  List<Task> _tasks;
  final _controller = StreamController<List<Task>>.broadcast();

  // Captures the last updateStatus call so a test can assert the drag wrote.
  String? lastUpdatedId;
  TaskStatus? lastUpdatedStatus;

  @override
  Stream<List<Task>> streamTasks(String repoId) async* {
    yield _tasks;
    yield* _controller.stream;
  }

  @override
  Future<void> updateStatus(
      String repoId, String taskId, TaskStatus status) async {
    lastUpdatedId = taskId;
    lastUpdatedStatus = status;
    _tasks = _tasks
        .map((t) => t.id == taskId ? _withStatus(t, status) : t)
        .toList();
    _controller.add(_tasks);
  }

  static Task _withStatus(Task t, TaskStatus status) => Task(
        id: t.id,
        title: t.title,
        description: t.description,
        status: status,
        assigneeId: t.assigneeId,
        dependsOn: t.dependsOn,
        source: t.source,
        createdBy: t.createdBy,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not stubbed');
}

Widget _harness(_StubTaskRepo repo) {
  return MaterialApp(
    home: MultiProvider(
      providers: [
        Provider<NavigationService>(create: (_) => NavigationService()),
        ChangeNotifierProvider<TasksBoardViewModel>(
          create: (_) =>
              TasksBoardViewModel(repoId: 'r1', taskRepository: repo),
        ),
      ],
      child: const TasksBoardPage(repoId: 'r1'),
    ),
  );
}

Task _task(String id, String title, TaskStatus status, {String? assignee}) =>
    Task(
      id: id,
      title: title,
      status: status,
      assigneeId: assignee,
      createdBy: 'u1',
    );

void main() {
  testWidgets('columns render CJK labels and count chips matching task counts',
      (tester) async {
    final repo = _StubTaskRepo([
      _task('t1', 'Alpha', TaskStatus.todo),
      _task('t2', 'Beta', TaskStatus.todo),
      _task('t3', 'Gamma', TaskStatus.inProgress),
      _task('t4', 'Delta', TaskStatus.done),
    ]);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    // Tabs + column labels (CJK).
    expect(find.text('看板'), findsOneWidget);
    expect(find.text('關聯圖'), findsOneWidget);
    expect(find.text('待辦'), findsOneWidget);
    expect(find.text('進行中'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    // Count chips reflect column sizes: todo=2, inProgress=1, done=1.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));

    // Cards show their titles.
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
  });

  testWidgets('long-press dragging a card to another column updates its status',
      (tester) async {
    final repo = _StubTaskRepo([
      _task('t1', 'Movable', TaskStatus.todo),
      _task('t3', 'Holder', TaskStatus.inProgress),
    ]);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    final cardFinder = find.text('Movable');
    final targetFinder = find.text('進行中');
    expect(cardFinder, findsOneWidget);

    // LongPressDraggable needs a long-press delay before it picks up: start a
    // gesture, hold, then move onto the 進行中 column and release.
    final gesture =
        await tester.startGesture(tester.getCenter(cardFinder));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(tester.getCenter(targetFinder));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(repo.lastUpdatedId, 't1');
    expect(repo.lastUpdatedStatus, TaskStatus.inProgress);
  });

  testWidgets('empty-state copy shows when there are no tasks', (tester) async {
    final repo = _StubTaskRepo(const []);
    await tester.pumpWidget(_harness(repo));
    await tester.pumpAndSettle();

    expect(find.text('您還未輸入專案架構'), findsOneWidget);
    expect(find.text('請點擊右下角 + 號來新增 TODOs'), findsOneWidget);
    // No column headers render in the empty state.
    expect(find.text('待辦'), findsNothing);
  });
}
