import 'package:flutter/foundation.dart';

import '../models/commit.dart';
import '../models/member.dart';
import '../models/task.dart';
import '../repositories/commit_repo.dart';
import '../repositories/user_repo.dart';
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
// MembersViewModel, plus an all-history commit fetch and async member-name
// resolution. Plug the two upstream VMs in via ChangeNotifierProxyProvider2.
//
// Three derivations:
//   * `contributions`       — per-member share of COMPLETED tasks (task basis).
//   * `commitContributions` — per-author share of ALL commits (commit basis),
//                             independent of the Daily page's loaded window.
//   * `memberProgress`      — per-member done/assigned progress + task list.
//
// Member labels resolve to GitHub names (users/{uid}.githubLogin, fallback
// .name, fallback uid) via UserRepository, cached so each uid is looked up once.
// Unassigned tasks are excluded from the task derivations.
class StatsViewModel with ChangeNotifier {
  StatsViewModel({
    required String repoId,
    CommitRepository? commitRepository,
    UserRepository? userRepository,
  })  : _repoId = repoId,
        _commitRepo = commitRepository ?? CommitRepository(),
        _userRepo = userRepository ?? UserRepository() {
    _loadAllCommits();
  }

  final String _repoId;
  final CommitRepository _commitRepo;
  final UserRepository _userRepo;

  TasksBoardViewModel? _tasksVm;
  MembersViewModel? _membersVm;

  // ---- All-history commits (commit basis) ----------------------------------

  List<Commit> _allCommits = const [];

  bool _commitsLoading = true;

  /// True while the one-shot all-history commit fetch is in flight. The commit
  /// basis pie shows a spinner until this clears.
  bool get commitsLoading => _commitsLoading;

  List<Contribution> _commitContributions = const [];

  /// Per-author share of ALL commits in the repo (label = author.login,
  /// fallback author.name, fallback 'unknown'). Always reflects the full
  /// history, never the Daily page's loaded window. See [computeCommitContributions].
  List<Contribution> get commitContributions => _commitContributions;

  Future<void> _loadAllCommits() async {
    try {
      _allCommits = await _commitRepo.fetchAllCommits(_repoId);
    } catch (_) {
      // Tolerate a fetch failure: degrade to an empty list so the tab still
      // renders (the task basis is unaffected).
      _allCommits = const [];
    } finally {
      _commitsLoading = false;
      _commitContributions = computeCommitContributions(_allCommits);
      notifyListeners();
    }
  }

  // ---- Member name resolution (githubLogin) --------------------------------

  // uid → resolved display label (githubLogin, fallback name, fallback uid).
  final Map<String, String> _names = {};
  // uids whose lookup is in flight, to avoid duplicate getUser calls.
  final Set<String> _resolving = {};

  /// Resolves each member's uid to a display label once, caching the result and
  /// notifying as each lookup lands so the labels refresh in place.
  void _resolveNames(List<Member> members) {
    for (final m in members) {
      final uid = m.userId;
      if (uid.isEmpty) continue;
      if (_names.containsKey(uid) || _resolving.contains(uid)) continue;
      _resolving.add(uid);
      _userRepo.getUser(uid).then((user) {
        _names[uid] = _labelFromUser(uid, user?.githubLogin, user?.name);
      }).catchError((_) {
        _names[uid] = uid; // tolerate lookup failure → raw uid
      }).whenComplete(() {
        _resolving.remove(uid);
        _recompute();
        notifyListeners();
      });
    }
  }

  static String _labelFromUser(String uid, String? githubLogin, String? name) {
    if (githubLogin != null && githubLogin.isNotEmpty) return githubLogin;
    if (name != null && name.isNotEmpty) return name;
    return uid;
  }

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
    _resolveNames(members.members);
    _recompute();
    notifyListeners();
  }

  void _recompute() {
    final tasks = _tasksVm?.tasks ?? const <Task>[];
    final members = _membersVm?.members ?? const <Member>[];

    _contributions = computeContributions(tasks, members, _names);
    _memberProgress = computeMemberProgress(tasks, members, _names);
  }

  /// Per-member share of all DONE tasks. Each member's pct = their done count /
  /// total done count across all assignees, rounded to an int (0..100). When no
  /// task is done team-wide every pct is 0 (zero-done edge). Only assignees with
  /// at least one done task get an entry; unassigned tasks are excluded. Sorted
  /// by done count descending, then by label. The [names] map (uid → resolved
  /// GitHub name) supplies labels; absent entries fall back to the raw id.
  /// Exposed for unit testing.
  static List<Contribution> computeContributions(
    List<Task> tasks,
    List<Member> members,
    Map<String, String> names,
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
          label: _labelFor(entry.key, byId, names),
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
  /// Sorted by pct descending, then by label. The [names] map (uid → resolved
  /// GitHub name) supplies labels; absent entries fall back to the raw id.
  /// Exposed for unit testing.
  static List<MemberProgress> computeMemberProgress(
    List<Task> tasks,
    List<Member> members,
    Map<String, String> names,
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
        label: _labelFor(entry.key, byId, names),
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

  /// Per-author share of ALL commits. Each author's pct = their commit count /
  /// total commit count, rounded to an int (0..100). Labels resolve to the
  /// commit author's GitHub login, falling back to author.name, then 'unknown'.
  /// Authors are grouped by that resolved label. Sorted by commit count
  /// descending, then by label. Empty when there are no commits. Exposed for
  /// unit testing.
  static List<Contribution> computeCommitContributions(List<Commit> commits) {
    final counts = <String, int>{};
    for (final c in commits) {
      final label = _commitAuthorLabel(c.author);
      counts.update(label, (v) => v + 1, ifAbsent: () => 1);
    }

    final total = counts.values.fold<int>(0, (a, b) => a + b);

    final list = [
      for (final entry in counts.entries)
        Contribution(
          assigneeId: entry.key,
          label: entry.key,
          doneCount: entry.value,
          pct: total == 0 ? 0 : ((entry.value / total) * 100).round(),
        ),
    ]..sort((a, b) {
        final byCount = b.doneCount.compareTo(a.doneCount);
        return byCount != 0 ? byCount : a.label.compareTo(b.label);
      });
    return list;
  }

  static String _commitAuthorLabel(CommitAuthor author) {
    if (author.login.isNotEmpty) return author.login;
    if (author.name.isNotEmpty) return author.name;
    return 'unknown';
  }

  // Resolves a member uid to its display label. Prefers the async-resolved
  // GitHub name in [names]; before that lands (or when the member is absent),
  // falls back to the raw uid — the only human-facing identifier available.
  static String _labelFor(
    String id,
    Map<String, Member> byId,
    Map<String, String> names,
  ) {
    final resolved = names[id];
    if (resolved != null && resolved.isNotEmpty) return resolved;
    return id; // not yet resolved / no match → raw id
  }
}
