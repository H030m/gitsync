import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_config.dart';
import '../models/sub_task.dart';
import 'fake/fake_functions_service.dart';

/// Single entry point for every Cloud Functions callable.
///
/// LIVE: hits the real Cloud Functions in `asia-east1`. Region must match
/// `functions/src/admin.ts::REGION`.
/// (See MEMORY.md 2026-05-27 "region locked to asia-east1".)
///
/// FAKE: returns canned data after a short delay. Useful while OpenAI /
/// GitHub / Discord secrets are not provisioned yet. The AI flow
/// implementations live in `functions/src/flows/*.ts` — once those are
/// done, flip `AppConfig.defaultBackend` to `Backend.live` and the same
/// API surface will hit real OpenAI.
///
/// TODO(handoff to D module — AI Agent owner):
/// real callable bodies are still `throw new Error('not implemented yet')`
/// stubs in `functions/src/flows/*.ts`. Until those are implemented,
/// `Backend.live` mode will surface those stub errors to the UI.
abstract class FunctionsService {
  factory FunctionsService() => AppConfig.useFakeBackend
      ? FakeFunctionsService()
      : _LiveFunctionsService();

  // ---- Repo management ---------------------------------------------------

  Future<String> addRepo({required String githubUrl});
  Future<void> removeRepo({required String repoId});

  // ---- AI flows ----------------------------------------------------------

  Future<List<SubTask>> breakdownTask({
    required String repoId,
    required String goal,
  });
  Future<void> forceUnlockBreakdown({required String repoId});
  Future<({String assigneeId, String reasoning})> assignTask({
    required String repoId,
    required String taskId,
  });
  Future<String> generateHandoff({
    required String repoId,
    required String taskId,
  });
  Future<String> summarizeDay({
    required String repoId,
    required String date,
  });

  // ---- Discord -----------------------------------------------------------

  Future<void> setDiscordWebhook({
    required String repoId,
    required String webhookUrl,
    required List<String> channelIds,
  });

  /// Enqueues an on-demand Discord backfill for [date] (YYYY-MM-DD). The
  /// always-on bot later claims the request, backfills the day's messages, and
  /// the backend produces a `discordDigests/{date}` doc. Returns the request id.
  Future<String> requestDiscordFetch({
    required String repoId,
    required String date,
  });

  // ---- FCM ---------------------------------------------------------------

  Future<void> subscribeToTopic({
    required String token,
    required String topic,
  });
}

class _LiveFunctionsService implements FunctionsService {
  _LiveFunctionsService()
      : _functions = FirebaseFunctions.instanceFor(region: 'asia-east1');

  final FirebaseFunctions _functions;

  HttpsCallable _callable(String name) => _functions.httpsCallable(name);

  @override
  Future<String> addRepo({required String githubUrl}) async {
    final res = await _callable('addRepo').call({'githubUrl': githubUrl});
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['repoId'] as String;
  }

  @override
  Future<void> removeRepo({required String repoId}) async {
    await _callable('removeRepo').call({'repoId': repoId});
  }

  @override
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

  @override
  Future<void> forceUnlockBreakdown({required String repoId}) async {
    await _callable('forceUnlockBreakdown').call({'repoId': repoId});
  }

  @override
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

  @override
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

  @override
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

  @override
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

  @override
  Future<String> requestDiscordFetch({
    required String repoId,
    required String date,
  }) async {
    final res = await _callable('requestDiscordFetch').call({
      'repoId': repoId,
      'date': date,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['requestId'] as String;
  }

  @override
  Future<void> subscribeToTopic({
    required String token,
    required String topic,
  }) async {
    await _callable('subscribeToTopic').call({'token': token, 'topic': topic});
  }
}
