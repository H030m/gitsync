import 'package:cloud_functions/cloud_functions.dart';

import '../config/app_config.dart';
import '../models/discord_chat.dart';
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

  /// Sets the Discord backfill start date (YYYY-MM-DD) for every channel bound
  /// to [repoId] and resets their watermarks so the next fetch re-pulls from
  /// the new start (existing messages are deduped, not duplicated).
  Future<void> setDiscordStartDate({
    required String repoId,
    required String startDate,
  });

  /// Sets the Discord backfill date range ([startDate]..[endDate], both
  /// YYYY-MM-DD) for every channel bound to [repoId] and resets their
  /// watermarks so the next fetch re-pulls the range (existing messages are
  /// deduped, not duplicated).
  Future<void> setDiscordRange({
    required String repoId,
    required String startDate,
    required String endDate,
  });

  /// Asks the AI to rewrite the digest for [date] (YYYY-MM-DD) per
  /// [instruction]. Returns the new markdown. Throws if the digest is locked.
  Future<String> editDiscordDigest({
    required String repoId,
    required String date,
    required String instruction,
  });

  /// Locks (freezes) or unlocks the digest for [date]. A locked digest is not
  /// changed by auto-regeneration or AI edits.
  Future<void> setDigestLock({
    required String repoId,
    required String date,
    required bool locked,
  });

  /// Asks the AI a question about this repo's Discord chat. The backend runs an
  /// agentic loop: it searches the ingested messages, then answers. Returns the
  /// answer plus the messages it surfaced (for the scrollable "sources" panel).
  /// [history] is prior turns, oldest first, for follow-up context.
  Future<DiscordChatReply> discordChat({
    required String repoId,
    required String question,
    List<DiscordChatTurn> history = const [],
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
  Future<void> setDiscordStartDate({
    required String repoId,
    required String startDate,
  }) async {
    await _callable('setDiscordStartDate').call({
      'repoId': repoId,
      'startDate': startDate,
    });
  }

  @override
  Future<void> setDiscordRange({
    required String repoId,
    required String startDate,
    required String endDate,
  }) async {
    await _callable('setDiscordRange').call({
      'repoId': repoId,
      'startDate': startDate,
      'endDate': endDate,
    });
  }

  @override
  Future<String> editDiscordDigest({
    required String repoId,
    required String date,
    required String instruction,
  }) async {
    final res = await _callable('editDiscordDigest').call({
      'repoId': repoId,
      'date': date,
      'instruction': instruction,
    });
    final data = Map<String, dynamic>.from(res.data as Map);
    return data['markdown'] as String;
  }

  @override
  Future<void> setDigestLock({
    required String repoId,
    required String date,
    required bool locked,
  }) async {
    await _callable('setDigestLock').call({
      'repoId': repoId,
      'date': date,
      'locked': locked,
    });
  }

  @override
  Future<DiscordChatReply> discordChat({
    required String repoId,
    required String question,
    List<DiscordChatTurn> history = const [],
  }) async {
    final res = await _callable('discordChat').call({
      'repoId': repoId,
      'question': question,
      'history': history.map((t) => t.toMap()).toList(),
    });
    return DiscordChatReply.fromMap(Map<String, dynamic>.from(res.data as Map));
  }

  @override
  Future<void> subscribeToTopic({
    required String token,
    required String topic,
  }) async {
    await _callable('subscribeToTopic').call({'token': token, 'topic': topic});
  }
}
