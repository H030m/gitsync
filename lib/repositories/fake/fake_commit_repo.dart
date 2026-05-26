import '../../config/app_config.dart';
import '../../data/dummy_data.dart';
import '../../models/commit.dart';
import '../commit_repo.dart';
import '_replay_state.dart';

class FakeCommitRepository implements CommitRepository {
  factory FakeCommitRepository() => _instance;
  FakeCommitRepository._internal();
  static final FakeCommitRepository _instance =
      FakeCommitRepository._internal();

  late final Map<String, ReplayState<List<Commit>>> _byRepo = {
    DummyData.demoRepoId: ReplayState<List<Commit>>(DummyData.commits),
  };

  ReplayState<List<Commit>> _state(String repoId) =>
      _byRepo.putIfAbsent(repoId, () => ReplayState<List<Commit>>(const []));

  @override
  Stream<List<Commit>> streamRecent(String repoId, {int limit = 50}) async* {
    yield _state(repoId).value.take(limit).toList();
    await for (final list in _state(repoId).stream) {
      yield list.take(limit).toList();
    }
  }

  @override
  Stream<List<Commit>> streamCommitsForDay(
      String repoId, DateTime day) async* {
    // Dummy: just yield everything (the seeded commits use the default
    // Timestamp.now() fallback). Good enough for UI smoke-testing.
    yield _state(repoId).value;
    await for (final list in _state(repoId).stream) {
      yield list;
    }
  }

  @override
  Future<Commit?> getCommit(String repoId, String sha) async {
    await Future.delayed(AppConfig.simulatedLatency);
    return _state(repoId).value.where((c) => c.sha == sha).firstOrNull;
  }
}
