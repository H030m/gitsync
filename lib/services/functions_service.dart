import 'package:cloud_functions/cloud_functions.dart';

import '../models/sub_task.dart';

// Single entry point for every Cloud Functions callable. Region is pinned to
// `us-west1` (MEMORY.md 2026-05-26 "Cloud Functions region locked to
// us-west1").
class FunctionsService {
  FunctionsService()
      : _functions = FirebaseFunctions.instanceFor(region: 'us-west1');

  final FirebaseFunctions _functions;

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  // ---- Repo management ---------------------------------------------------

  Future<String> addRepo({required String githubUrl}) async {
    final res = await _callable('addRepo').call({'githubUrl': githubUrl});
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['repoId'] as String;
  }

  Future<void> removeRepo({required String repoId}) async {
    await _callable('removeRepo').call({'repoId': repoId});
  }

  // ---- AI flows ----------------------------------------------------------

  Future<List<SubTask>> breakdownTask({
    required String repoId,
    required String goal,
  }) async {
    final res = await _callable('breakdownTask').call({
      'repoId': repoId,
      'goal': goal,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (data['subtasks'] as List)
        .map((m) => SubTask.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<void> forceUnlockBreakdown({required String repoId}) async {
    await _callable('forceUnlockBreakdown').call({'repoId': repoId});
  }

  Future<({String assigneeId, String reasoning})> assignTask({
    required String repoId,
    required String taskId,
  }) async {
    final res = await _callable('assignTask').call({
      'repoId': repoId,
      'taskId': taskId,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return (
      assigneeId: data['assigneeId'] as String,
      reasoning: data['reasoning'] as String,
    );
  }

  Future<String> generateHandoff({
    required String repoId,
    required String taskId,
  }) async {
    final res = await _callable('generateHandoff').call({
      'repoId': repoId,
      'taskId': taskId,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['handoffMarkdown'] as String;
  }

  Future<String> summarizeDay({
    required String repoId,
    required String date,
  }) async {
    final res = await _callable('summarizeDay').call({
      'repoId': repoId,
      'date': date,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['summary'] as String;
  }

  // ---- Discord -----------------------------------------------------------

  Future<void> setDiscordWebhook({
    required String repoId,
    required String webhookUrl,
    required List<String> channelIds,
  }) async {
    await _callable('setDiscordWebhook').call({
      'repoId': repoId,
      'webhookUrl': webhookUrl,
      'channelIds': channelIds,
    });
  }

  // ---- FCM ---------------------------------------------------------------

  Future<void> subscribeToTopic({
    required String token,
    required String topic,
  }) async {
    await _callable('subscribeToTopic').call({'token': token, 'topic': topic});
  }
}
