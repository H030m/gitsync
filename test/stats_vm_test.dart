import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gitsync/models/commit.dart';
import 'package:gitsync/models/member.dart';
import 'package:gitsync/models/task.dart';
import 'package:gitsync/view_models/stats_vm.dart';

Commit _commit(String sha, DateTime committedAt, {String login = 'x'}) => Commit(
      sha: sha,
      repoId: 'r',
      message: 'm',
      author: CommitAuthor(login: login, name: login, email: '$login@x'),
      url: '',
      committedAt: Timestamp.fromDate(committedAt),
    );

Task _task(String id, TaskStatus status, {String? assigneeId}) => Task(
      id: id,
      title: id,
      status: status,
      assigneeId: assigneeId,
      createdBy: 'u',
    );

Member _member(String id) => Member(userId: id, role: MemberRole.member);

void main() {
  group('computeCommitsPerDay', () {
    final now = DateTime(2026, 6, 6, 10, 30); // fixed "today"

    test('returns exactly 14 zero-filled days, oldest first, today inclusive',
        () {
      final days = StatsViewModel.computeCommitsPerDay(const [], now: now);

      expect(days.length, StatsViewModel.trendDays);
      expect(days.length, 14);
      // Oldest is today − 13 days, newest is today.
      expect(days.first.day, DateTime(2026, 5, 24));
      expect(days.last.day, DateTime(2026, 6, 6));
      expect(days.every((d) => d.count == 0), isTrue);
    });

    test('buckets commits into the right day regardless of time of day', () {
      final commits = [
        _commit('a', DateTime(2026, 6, 6, 0, 1)), // today, just past midnight
        _commit('b', DateTime(2026, 6, 6, 23, 59)), // today, late
        _commit('c', DateTime(2026, 6, 5, 12)), // yesterday
      ];

      final days = StatsViewModel.computeCommitsPerDay(commits, now: now);
      final byDay = {for (final d in days) d.day: d.count};

      expect(byDay[DateTime(2026, 6, 6)], 2);
      expect(byDay[DateTime(2026, 6, 5)], 1);
      expect(byDay[DateTime(2026, 6, 4)], 0); // an empty day stays zero-filled
    });

    test('excludes commits outside the 14-day window (older and future)', () {
      final commits = [
        _commit('old', DateTime(2026, 5, 23, 12)), // 1 day before window start
        _commit('edge', DateTime(2026, 5, 24, 12)), // first day in window
        _commit('future', DateTime(2026, 6, 7, 9)), // tomorrow, after today
      ];

      final days = StatsViewModel.computeCommitsPerDay(commits, now: now);
      final total = days.fold<int>(0, (a, d) => a + d.count);

      expect(total, 1); // only the in-window 'edge' commit counts
      final byDay = {for (final d in days) d.day: d.count};
      expect(byDay[DateTime(2026, 5, 24)], 1);
    });
  });

  group('computeMemberLoad', () {
    test('counts in-progress and done per assignee, skips todo + unassigned',
        () {
      final tasks = [
        _task('1', TaskStatus.inProgress, assigneeId: 'alice'),
        _task('2', TaskStatus.inProgress, assigneeId: 'alice'),
        _task('3', TaskStatus.done, assigneeId: 'alice'),
        _task('4', TaskStatus.todo, assigneeId: 'alice'), // ignored
        _task('5', TaskStatus.done, assigneeId: 'bob'),
        _task('6', TaskStatus.todo, assigneeId: 'carol'), // todo-only → absent
        _task('7', TaskStatus.inProgress), // unassigned → ignored
      ];
      final members = [_member('alice'), _member('bob'), _member('carol')];

      final loads = StatsViewModel.computeMemberLoad(tasks, members);
      final byId = {for (final l in loads) l.assigneeId: l};

      // carol has only a todo task → no entry; unassigned never appears.
      expect(byId.keys.toSet(), {'alice', 'bob'});
      expect(byId['alice']!.inProgress, 2);
      expect(byId['alice']!.done, 1);
      expect(byId['alice']!.total, 3);
      expect(byId['bob']!.inProgress, 0);
      expect(byId['bob']!.done, 1);
    });

    test('sorts by total descending', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'low'),
        _task('2', TaskStatus.inProgress, assigneeId: 'high'),
        _task('3', TaskStatus.inProgress, assigneeId: 'high'),
        _task('4', TaskStatus.done, assigneeId: 'high'),
      ];
      final loads = StatsViewModel.computeMemberLoad(
        tasks,
        [_member('low'), _member('high')],
      );

      expect(loads.first.assigneeId, 'high');
      expect(loads.last.assigneeId, 'low');
    });

    test('falls back to the raw id when the assignee is not in the roster', () {
      final tasks = [
        _task('1', TaskStatus.inProgress, assigneeId: 'ghost-user'),
      ];
      // Empty roster → no member match.
      final loads = StatsViewModel.computeMemberLoad(tasks, const []);

      expect(loads.length, 1);
      expect(loads.single.assigneeId, 'ghost-user');
      expect(loads.single.label, 'ghost-user'); // raw id used as the label
    });

    test('joins the roster member when present', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'alice'),
      ];
      final loads =
          StatsViewModel.computeMemberLoad(tasks, [_member('alice')]);

      expect(loads.single.label, 'alice');
    });
  });
}
