import '../../config/app_config.dart';
import '../../data/dummy_data.dart';
import '../../models/sub_task.dart';
import '../functions_service.dart';

/// Canned Cloud Functions responses for fake-backend mode. All methods
/// settle after [AppConfig.simulatedLatency] so loading spinners are visible.
class FakeFunctionsService implements FunctionsService {
  factory FakeFunctionsService() => _instance;
  FakeFunctionsService._internal();
  static final FakeFunctionsService _instance =
      FakeFunctionsService._internal();

  // ---- Repo management ---------------------------------------------------

  @override
  Future<String> addRepo({required String githubUrl}) async {
    await Future.delayed(AppConfig.simulatedLatency * 4);
    // Pretend we registered the repo and got an ID back.
    return DummyData.demoRepoId;
  }

  @override
  Future<void> removeRepo({required String repoId}) async {
    await Future.delayed(AppConfig.simulatedLatency * 2);
  }

  // ---- AI flows ----------------------------------------------------------

  @override
  Future<List<SubTask>> breakdownTask({
    required String repoId,
    required String goal,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 6);
    // Pretend the LLM split the goal into 4 generic subtasks.
    return [
      SubTask(
        id: 'fake-sub-001',
        title: 'Sketch UI for "$goal"',
        description: 'Lay out screens and routes; pick widgets.',
        dependsOn: const [],
        estimatedHours: 2,
      ),
      SubTask(
        id: 'fake-sub-002',
        title: 'Model + Repository for "$goal"',
        description: 'Add Firestore model and CRUD wiring.',
        dependsOn: const ['fake-sub-001'],
        estimatedHours: 3,
      ),
      SubTask(
        id: 'fake-sub-003',
        title: 'ViewModel + state flow',
        description: 'ChangeNotifier with stream subscription.',
        dependsOn: const ['fake-sub-002'],
        estimatedHours: 2,
      ),
      SubTask(
        id: 'fake-sub-004',
        title: 'Wire UI to ViewModel + smoke test',
        description: 'Provider hookup; manual test on Android emulator.',
        dependsOn: const ['fake-sub-001', 'fake-sub-003'],
        estimatedHours: 1.5,
      ),
    ];
  }

  @override
  Future<void> forceUnlockBreakdown({required String repoId}) async {
    await Future.delayed(AppConfig.simulatedLatency);
  }

  @override
  Future<({String assigneeId, String reasoning})> assignTask({
    required String repoId,
    required String taskId,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 5);
    return (
      assigneeId: DummyData.aliceId,
      reasoning:
          'Alice has the lowest activeIssueCount (3) and her expertiseTags '
          'include "backend" + "firestore", which match this task.',
    );
  }

  @override
  Future<String> generateHandoff({
    required String repoId,
    required String taskId,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 8);
    return '''
## What was done
- Implemented $taskId end-to-end with tests.
- Wired into the matching ViewModel via Provider.

## Why this way
- Followed the course MVVM layering (View → ViewModel → Repository → Firestore).
- Used `provider` over Riverpod to stay consistent with the rest of the codebase.

## What's left for the next engineer
- Add a confirmation dialog before destructive actions.
- Move colors from hardcoded hex to `Theme.of(ctx).colorScheme.X`.

## Gotchas
- The Firestore listener may emit twice on cold start — guard with `if (mounted)`.
- This is a FAKE handoff generated in debug mode; the real one comes from the
  `generateHandoffFlow` Cloud Function once it is implemented.
''';
  }

  @override
  Future<String> summarizeDay({
    required String repoId,
    required String date,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 4);
    return DummyData.todayReport.summary;
  }

  // ---- Discord -----------------------------------------------------------

  @override
  Future<void> setDiscordWebhook({
    required String repoId,
    required String webhookUrl,
    required List<String> channelIds,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency);
  }

  // ---- FCM ---------------------------------------------------------------

  @override
  Future<void> subscribeToTopic({
    required String token,
    required String topic,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency);
  }
}
