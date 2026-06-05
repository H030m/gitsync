import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/task.dart';
import 'members_vm.dart';
import 'tasks_board_vm.dart';

/// One member's share of the team's completed (done) tasks.
@immutable
class Contribution {
  const Contribution({
    required this.assigneeId,
    required this.label,
    required this.doneCount,
    required this.pct,
  });

  final String assigneeId;

  /// Display label for the member — the roster has no human-readable name
  /// field today, so this falls back to the raw assigneeId.
  final String label;

  /// Number of done tasks assigned to this member.
  final int doneCount;

  /// This member's share of ALL done tasks, 0..100 (rounded). When no task is
  /// done across the team every share is 0.
  final int pct;
}

/// One member's progress over their own assigned tasks, with the task list.
@immutable
class MemberProgress {
  const MemberProgress({
    required this.assigneeId,
    required this.label,
    required this.pct,
    required this.tasks,
  });

  final String assigneeId;
  final String label;

  /// done / (all tasks assigned to this member), 0..100 (rounded).
  final int pct;

  /// This member's tasks, pending first then done, each in original order.
  final List<ProgressTask> tasks;
}

/// A single task line in a member's progress detail list.
@immutable
class ProgressTask {
  const ProgressTask({required this.title, required this.done});

  final String title;
  final bool done;
}

// Derived statistics view (StatsViewPage) built from TasksBoardViewModel and
// MembersViewModel. Plug both in via ChangeNotifierProxyProvider2 in the page.
//
// Two derivations, mirroring the design prototype's two tabs:
//   * `contributions`  — per-member share of COMPLETED tasks (貢獻度 pie).
//   * `memberProgress` — per-member done/assigned progress + task list (進度表).
//
// Unassigned tasks are excluded from both.
class StatsViewModel with ChangeNotifier {
  TasksBoardViewModel? _tasksVm;
  MembersViewModel? _membersVm;

  List<Contribution> _contributions = const [];

  /// Per-member share of all done tasks, members with at least one done task
  /// first (by done count descending), then any remaining roster/assignee with
  /// zero done. See [computeContributions].
  List<Contribution> get contributions => _contributions;

  List<MemberProgress> _memberProgress = const [];

  /// Per-member done/assigned progress with their ordered task list, one entry
  /// per member that has at least one assigned task. See [computeMemberProgress].
  List<MemberProgress> get memberProgress => _memberProgress;

  // Receives upstream updates from ChangeNotifierProxyProvider2.
  void updateFromUpstream({
    required TasksBoardViewModel tasks,
    required MembersViewModel members,
  }) {
    _tasksVm = tasks;
    _membersVm = members;
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final tasks = _tasksVm?.tasks ?? const <Task>[];
    final members = _membersVm?.members ?? const <Member>[];

    _contributions = computeContributions(tasks, members);
    _memberProgress = computeMemberProgress(tasks, members);
  }

  /// Per-member share of all DONE tasks. Each member's pct = their done count /
  /// total done count across all assignees, rounded to an int (0..100). When no
  /// task is done team-wide every pct is 0 (zero-done edge). Only assignees with
  /// at least one done task get an entry; unassigned tasks are excluded. Sorted
  /// by done count descending, then by label. Exposed for unit testing.
  static List<Contribution> computeContributions(
    List<Task> tasks,
    List<Member> members,
  ) {
    final byId = {for (final m in members) m.userId: m};

    final done = <String, int>{};
    for (final t in tasks) {
      final id = t.assigneeId;
      if (id == null || id.isEmpty) continue;
      if (t.status != TaskStatus.done) continue;
      done.update(id, (v) => v + 1, ifAbsent: () => 1);
    }

    final totalDone = done.values.fold<int>(0, (a, b) => a + b);

    final list = [
      for (final entry in done.entries)
        Contribution(
          assigneeId: entry.key,
          label: _labelFor(entry.key, byId),
          doneCount: entry.value,
          pct: totalDone == 0
              ? 0
              : ((entry.value / totalDone) * 100).round(),
        ),
    ]..sort((a, b) {
        final byCount = b.doneCount.compareTo(a.doneCount);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
    return list;
  }

  /// Per-member progress over their OWN assigned tasks. pct = done / assigned
  /// count, rounded (0..100). Each entry's task list is ordered pending-first
  /// then done, preserving original order within each group. Only assignees with
  /// at least one assigned task get an entry; unassigned tasks are excluded.
  /// Sorted by pct descending, then by label. Exposed for unit testing.
  static List<MemberProgress> computeMemberProgress(
    List<Task> tasks,
    List<Member> members,
  ) {
    final byId = {for (final m in members) m.userId: m};

    final byAssignee = <String, List<Task>>{};
    for (final t in tasks) {
      final id = t.assigneeId;
      if (id == null || id.isEmpty) continue;
      byAssignee.putIfAbsent(id, () => []).add(t);
    }

    final list = <MemberProgress>[];
    for (final entry in byAssignee.entries) {
      final assigned = entry.value;
      final doneCount =
          assigned.where((t) => t.status == TaskStatus.done).length;
      final pct = assigned.isEmpty
          ? 0
          : ((doneCount / assigned.length) * 100).round();

      final pending = [
        for (final t in assigned)
          if (t.status != TaskStatus.done)
            ProgressTask(title: t.title, done: false),
      ];
      final completed = [
        for (final t in assigned)
          if (t.status == TaskStatus.done)
            ProgressTask(title: t.title, done: true),
      ];

      list.add(MemberProgress(
        assigneeId: entry.key,
        label: _labelFor(entry.key, byId),
        pct: pct,
        tasks: [...pending, ...completed],
      ));
    }

    list.sort((a, b) {
      final byPct = b.pct.compareTo(a.pct);
      return byPct != 0 ? byPct : a.label.compareTo(b.label);
    });
    return list;
  }

  // The roster has no display-name field yet; resolve to the raw id whether or
  // not the member is present. Kept as a join point so a future name field on
  // Member only needs to change here (mirrors how the rest of the UI shows
  // assignees: the userId is the only human-facing identifier available).
  static String _labelFor(String id, Map<String, Member> byId) {
    final member = byId[id];
    if (member == null) return id; // no member match → raw id
    return member.userId;
  }
}
