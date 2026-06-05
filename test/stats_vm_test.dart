import 'package:flutter_test/flutter_test.dart';

import 'package:gitsync/models/member.dart';
import 'package:gitsync/models/task.dart';
import 'package:gitsync/view_models/stats_vm.dart';

Task _task(
  String id,
  TaskStatus status, {
  String? assigneeId,
  String? title,
}) =>
    Task(
      id: id,
      title: title ?? id,
      status: status,
      assigneeId: assigneeId,
      createdBy: 'u',
    );

Member _member(String id) => Member(userId: id, role: MemberRole.member);

void main() {
  group('computeContributions', () {
    test('per-member share of done tasks, sorted by done count desc', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice'),
        _task('2', TaskStatus.done, assigneeId: 'alice'),
        _task('3', TaskStatus.done, assigneeId: 'bob'),
        _task('4', TaskStatus.inProgress, assigneeId: 'alice'), // not done
        _task('5', TaskStatus.todo, assigneeId: 'bob'), // not done
      ];
      final members = [_member('alice'), _member('bob')];

      final contribs = StatsViewModel.computeContributions(tasks, members);

      // 3 done total: alice 2 (67%), bob 1 (33%). alice first (higher count).
      expect(contribs.map((c) => c.assigneeId).toList(), ['alice', 'bob']);
      expect(contribs.first.doneCount, 2);
      expect(contribs.first.pct, 67); // 2/3 rounds to 67
      expect(contribs.last.doneCount, 1);
      expect(contribs.last.pct, 33); // 1/3 rounds to 33
    });

    test('excludes unassigned and never-done assignees', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice'),
        _task('2', TaskStatus.done), // unassigned → excluded
        _task('3', TaskStatus.todo, assigneeId: 'bob'), // never done → no entry
      ];
      final contribs = StatsViewModel.computeContributions(
        tasks,
        [_member('alice'), _member('bob')],
      );

      expect(contribs.length, 1);
      expect(contribs.single.assigneeId, 'alice');
      expect(contribs.single.pct, 100);
    });

    test('zero-done edge: no done tasks → empty list', () {
      final tasks = [
        _task('1', TaskStatus.todo, assigneeId: 'alice'),
        _task('2', TaskStatus.inProgress, assigneeId: 'bob'),
      ];
      final contribs = StatsViewModel.computeContributions(
        tasks,
        [_member('alice'), _member('bob')],
      );

      expect(contribs, isEmpty);
    });

    test('falls back to the raw id when the assignee is not in the roster', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'ghost-user'),
      ];
      final contribs = StatsViewModel.computeContributions(tasks, const []);

      expect(contribs.single.label, 'ghost-user');
    });
  });

  group('computeMemberProgress', () {
    test('pct = done / assigned, rounded', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice'),
        _task('2', TaskStatus.done, assigneeId: 'alice'),
        _task('3', TaskStatus.todo, assigneeId: 'alice'),
        _task('4', TaskStatus.inProgress, assigneeId: 'alice'),
      ];
      final progress = StatsViewModel.computeMemberProgress(
        tasks,
        [_member('alice')],
      );

      // 2 done of 4 assigned → 50%.
      expect(progress.single.pct, 50);
      expect(progress.single.tasks.length, 4);
    });

    test('task list is ordered pending-first, then done, preserving order', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice', title: 'doneA'),
        _task('2', TaskStatus.todo, assigneeId: 'alice', title: 'todoA'),
        _task('3', TaskStatus.done, assigneeId: 'alice', title: 'doneB'),
        _task('4', TaskStatus.inProgress, assigneeId: 'alice', title: 'wipA'),
      ];
      final progress = StatsViewModel.computeMemberProgress(
        tasks,
        [_member('alice')],
      );

      final titles = progress.single.tasks.map((t) => t.title).toList();
      // pending (todoA, wipA) keep original order, then done (doneA, doneB).
      expect(titles, ['todoA', 'wipA', 'doneA', 'doneB']);
      expect(progress.single.tasks.map((t) => t.done).toList(),
          [false, false, true, true]);
    });

    test('excludes unassigned tasks; one entry per assignee', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice'),
        _task('2', TaskStatus.todo, assigneeId: 'bob'),
        _task('3', TaskStatus.done), // unassigned → excluded
      ];
      final progress = StatsViewModel.computeMemberProgress(
        tasks,
        [_member('alice'), _member('bob')],
      );

      expect(progress.map((p) => p.assigneeId).toSet(), {'alice', 'bob'});
      // alice 1/1 = 100, bob 0/1 = 0; sorted pct desc → alice first.
      expect(progress.first.assigneeId, 'alice');
      expect(progress.first.pct, 100);
      expect(progress.last.assigneeId, 'bob');
      expect(progress.last.pct, 0);
    });

    test('falls back to the raw id when not in the roster', () {
      final tasks = [
        _task('1', TaskStatus.todo, assigneeId: 'ghost-user'),
      ];
      final progress =
          StatsViewModel.computeMemberProgress(tasks, const []);

      expect(progress.single.label, 'ghost-user');
      expect(progress.single.pct, 0);
    });
  });
}
