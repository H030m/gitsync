import 'package:flutter_test/flutter_test.dart';

import 'package:gitsync/models/app_user.dart';
import 'package:gitsync/models/commit.dart';
import 'package:gitsync/models/member.dart';
import 'package:gitsync/models/task.dart';
import 'package:gitsync/repositories/commit_repo.dart';
import 'package:gitsync/repositories/member_repo.dart';
import 'package:gitsync/repositories/task_repo.dart';
import 'package:gitsync/repositories/user_repo.dart';
import 'package:gitsync/view_models/members_vm.dart';
import 'package:gitsync/view_models/stats_vm.dart';
import 'package:gitsync/view_models/tasks_board_vm.dart';

Commit _commit(String login, {String name = '', String? sha}) => Commit(
      sha: sha ?? login + DateTime.now().microsecondsSinceEpoch.toString(),
      repoId: 'r',
      message: 'm',
      author: CommitAuthor(login: login, name: name, email: ''),
      url: '',
    );

// Hand-rolled fakes (mirrors the repo's other inline test fakes).
class _FakeCommitRepo implements CommitRepository {
  _FakeCommitRepo(this.commits);
  final List<Commit> commits;

  @override
  Future<List<Commit>> fetchAllCommits(String repoId) async => commits;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserRepo implements UserRepository {
  _FakeUserRepo(this.users);
  // uid → user (absent uid resolves to null).
  final Map<String, AppUser> users;

  @override
  Future<AppUser?> getUser(String userId) async => users[userId];

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AppUser _user(String id, {String githubLogin = '', String name = ''}) =>
    AppUser(
      id: id,
      name: name,
      email: '',
      avatarUrl: '',
      githubLogin: githubLogin,
    );

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

      final contribs =
          StatsViewModel.computeContributions(tasks, members, const {});

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
        const {},
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
        const {},
      );

      expect(contribs, isEmpty);
    });

    test('falls back to the raw id when the assignee is not in the roster', () {
      final tasks = [
        _task('1', TaskStatus.done, assigneeId: 'ghost-user'),
      ];
      final contribs =
          StatsViewModel.computeContributions(tasks, const [], const {});

      expect(contribs.single.label, 'ghost-user');
    });

    test('uses the resolved-name map for labels when present', () {
      final tasks = [_task('1', TaskStatus.done, assigneeId: 'alice')];
      final contribs = StatsViewModel.computeContributions(
        tasks,
        [_member('alice')],
        const {'alice': 'alice-dev'},
      );

      expect(contribs.single.label, 'alice-dev');
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
        const {},
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
        const {},
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
        const {},
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
          StatsViewModel.computeMemberProgress(tasks, const [], const {});

      expect(progress.single.label, 'ghost-user');
      expect(progress.single.pct, 0);
    });
  });

  group('computeCommitContributions', () {
    test('per-author share of all commits, sorted by count desc', () {
      final commits = [
        _commit('alice-dev'),
        _commit('alice-dev'),
        _commit('bob-ml'),
        _commit('alice-dev'),
      ];
      final contribs = StatsViewModel.computeCommitContributions(commits);

      // 4 commits: alice-dev 3 (75%), bob-ml 1 (25%).
      expect(contribs.map((c) => c.label).toList(), ['alice-dev', 'bob-ml']);
      expect(contribs.first.doneCount, 3);
      expect(contribs.first.pct, 75);
      expect(contribs.last.doneCount, 1);
      expect(contribs.last.pct, 25);
    });

    test('no commits → empty list', () {
      expect(StatsViewModel.computeCommitContributions(const []), isEmpty);
    });

    test('falls back to author.name, then "unknown", for the label', () {
      final commits = [
        _commit('', name: 'No Login'),
        _commit('', name: ''), // neither → 'unknown'
      ];
      final contribs = StatsViewModel.computeCommitContributions(commits);

      expect(contribs.map((c) => c.label).toSet(), {'No Login', 'unknown'});
    });
  });

  group('name resolution via StatsViewModel', () {
    test('resolves member uids to githubLogin, falling back to name then uid',
        () async {
      final vm = StatsViewModel(
        repoId: 'r',
        commitRepository: _FakeCommitRepo(const []),
        userRepository: _FakeUserRepo({
          'u-login': _user('u-login', githubLogin: 'octocat'),
          'u-name': _user('u-name', name: 'Just A Name'),
          // 'u-missing' is absent → getUser returns null → falls back to uid.
        }),
      );

      vm.updateFromUpstream(
        tasks: _StubTasks([
          _task('1', TaskStatus.done, assigneeId: 'u-login'),
          _task('2', TaskStatus.done, assigneeId: 'u-name'),
          _task('3', TaskStatus.done, assigneeId: 'u-missing'),
        ]),
        members: _StubMembers([
          _member('u-login'),
          _member('u-name'),
          _member('u-missing'),
        ]),
      );

      // Let the async getUser lookups land.
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final labels = {
        for (final c in vm.contributions) c.assigneeId: c.label,
      };
      expect(labels['u-login'], 'octocat');
      expect(labels['u-name'], 'Just A Name');
      expect(labels['u-missing'], 'u-missing');
    });
  });
}

// Minimal upstream-VM stubs so updateFromUpstream can be exercised without the
// real backend-wired view models.
class _StubTasks extends TasksBoardViewModel {
  _StubTasks(this._tasks) : super(repoId: 'r', taskRepository: _NoopTaskRepo());
  final List<Task> _tasks;
  @override
  List<Task> get tasks => _tasks;
}

class _StubMembers extends MembersViewModel {
  _StubMembers(this._members)
      : super(repoId: 'r', memberRepository: _NoopMemberRepo());
  final List<Member> _members;
  @override
  List<Member> get members => _members;
}

class _NoopTaskRepo implements TaskRepository {
  @override
  Stream<List<Task>> streamTasks(String repoId) => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopMemberRepo implements MemberRepository {
  @override
  Stream<List<Member>> streamMembers(String repoId) => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
