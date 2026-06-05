import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/task.dart';
import 'commits_vm.dart';
import 'members_vm.dart';
import 'tasks_board_vm.dart';

/// One member's task workload, split by status.
@immutable
class MemberLoad {
  const MemberLoad({
    required this.assigneeId,
    required this.label,
    required this.inProgress,
    required this.done,
  });

  final String assigneeId;

  /// Display label for the assignee — the member roster has no human-readable
  /// name field today, so this falls back to the raw assigneeId. When the id is
  /// absent from the roster (no member match) the raw id is used directly.
  final String label;
  final int inProgress;
  final int done;

  int get total => inProgress + done;
}

/// One calendar day's commit count (used by the 14-day trend).
@immutable
class DayCount {
  const DayCount({required this.day, required this.count});

  /// Midnight (local) of the bucketed day.
  final DateTime day;
  final int count;
}

// Derived statistics view (StatsViewPage) built from TasksBoardViewModel,
// CommitsViewModel and MembersViewModel. Plug all three in via
// ChangeNotifierProxyProvider3 in the route layer.
//
// CAVEAT: the commit-derived charts (`commitsPerAuthor`, `commitsPerDay`) only
// see the commits currently loaded by CommitsViewModel — i.e. the recent-50
// window, or the user-picked day range on the Daily page. They are not a
// separate full-history query (by design — see task 06-06 prd §5).
class StatsViewModel with ChangeNotifier {
  /// Length of the daily-commits trend window, in days (today inclusive).
  static const int trendDays = 14;

  TasksBoardViewModel? _tasksVm;
  CommitsViewModel? _commitsVm;
  MembersViewModel? _membersVm;

  Map<TaskStatus, int> _statusCounts = const {};
  Map<TaskStatus, int> get statusCounts => _statusCounts;

  Map<String, int> _commitsPerAuthor = const {};
  Map<String, int> get commitsPerAuthor => _commitsPerAuthor;

  List<DayCount> _commitsPerDay = const [];

  /// Commit counts for exactly the last [trendDays] calendar days (oldest →
  /// newest, today inclusive), zero-filled. Derived from the loaded commits'
  /// `committedAt`; commits outside the window are excluded.
  List<DayCount> get commitsPerDay => _commitsPerDay;

  List<MemberLoad> _memberLoad = const [];

  /// Per-assignee in-progress/done counts, one entry per assignee that has at
  /// least one in-progress or done task, sorted by total descending.
  List<MemberLoad> get memberLoad => _memberLoad;

  // Receives upstream updates from ChangeNotifierProxyProvider3.
  void updateFromUpstream({
    required TasksBoardViewModel tasks,
    required CommitsViewModel commits,
    required MembersViewModel members,
  }) {
    _tasksVm = tasks;
    _commitsVm = commits;
    _membersVm = members;
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final tasks = _tasksVm?.tasks ?? const <Task>[];
    final commits = _commitsVm?.commits ?? const [];
    final members = _membersVm?.members ?? const <Member>[];

    _statusCounts = _computeStatusCounts(tasks);
    _commitsPerAuthor = _computeCommitsPerAuthor(commits);
    _commitsPerDay = computeCommitsPerDay(commits);
    _memberLoad = computeMemberLoad(tasks, members);
  }

  static Map<TaskStatus, int> _computeStatusCounts(List<Task> tasks) {
    final counts = <TaskStatus, int>{
      TaskStatus.todo: 0,
      TaskStatus.inProgress: 0,
      TaskStatus.done: 0,
    };
    for (final t in tasks) {
      counts[t.status] = (counts[t.status] ?? 0) + 1;
    }
    return counts;
  }

  static Map<String, int> _computeCommitsPerAuthor(Iterable commits) {
    final perAuthor = <String, int>{};
    for (final c in commits) {
      perAuthor.update(c.author.login, (v) => v + 1, ifAbsent: () => 1);
    }
    return perAuthor;
  }

  /// Buckets [commits] into the last [trendDays] calendar days (today
  /// inclusive), zero-filling empty days and dropping commits outside the
  /// window. Returned oldest → newest. Exposed for unit testing.
  static List<DayCount> computeCommitsPerDay(
    Iterable commits, {
    DateTime? now,
  }) {
    final today = _dayOf(now ?? DateTime.now());
    final start = today.subtract(const Duration(days: trendDays - 1));

    // Seed every day in the window with a zero count, keyed by ymd.
    final buckets = <String, int>{};
    for (var i = 0; i < trendDays; i++) {
      buckets[_ymd(start.add(Duration(days: i)))] = 0;
    }

    for (final c in commits) {
      final day = _dayOf(c.committedAt.toDate());
      if (day.isBefore(start) || day.isAfter(today)) continue; // out of window
      final key = _ymd(day);
      buckets[key] = (buckets[key] ?? 0) + 1;
    }

    return [
      for (var i = 0; i < trendDays; i++)
        DayCount(
          day: start.add(Duration(days: i)),
          count: buckets[_ymd(start.add(Duration(days: i)))] ?? 0,
        ),
    ];
  }

  /// Per-assignee {inProgress, done} counts from [tasks], joined to a display
  /// label via the [members] roster. The roster exposes no human-readable name
  /// today, so the label is the assigneeId either way; an assigneeId absent
  /// from the roster (no member match) still resolves to the raw id. Unassigned
  /// tasks and todo-only assignees are skipped. Exposed for unit testing.
  static List<MemberLoad> computeMemberLoad(
    List<Task> tasks,
    List<Member> members,
  ) {
    final byId = {for (final m in members) m.userId: m};

    final inProgress = <String, int>{};
    final done = <String, int>{};
    for (final t in tasks) {
      final id = t.assigneeId;
      if (id == null || id.isEmpty) continue;
      switch (t.status) {
        case TaskStatus.inProgress:
          inProgress.update(id, (v) => v + 1, ifAbsent: () => 1);
        case TaskStatus.done:
          done.update(id, (v) => v + 1, ifAbsent: () => 1);
        case TaskStatus.todo:
          break;
      }
    }

    final ids = {...inProgress.keys, ...done.keys};
    final loads = [
      for (final id in ids)
        MemberLoad(
          assigneeId: id,
          label: _labelFor(id, byId),
          inProgress: inProgress[id] ?? 0,
          done: done[id] ?? 0,
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));
    return loads;
  }

  // The roster has no display-name field yet; resolve to the raw id whether or
  // not the member is present. Kept as a join point so a future name field on
  // Member only needs to change here.
  static String _labelFor(String id, Map<String, Member> byId) {
    final member = byId[id];
    if (member == null) return id; // no member match → raw id
    return member.userId;
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
