import '../../config/app_config.dart';
import '../../data/dummy_data.dart';
import '../../models/daily_brief.dart';
import '../../models/discord_chat.dart';
import '../../models/sub_task.dart';
import '../../repositories/fake/fake_discord_digest_repo.dart';
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

  @override
  Future<DailyBriefReply> dailyBrief({
    required String repoId,
    required String date,
    required String question,
    List<DailyBriefTurn> history = const [],
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 3);

    // Keyword-match the demo commits the same way the backend tool does, so the
    // fake answer cites real "sources" in the panel.
    final terms = question
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9一-鿿]+'))
        .where((t) => t.length >= 2)
        .toSet();
    final commits = DummyData.commits;
    final matched = commits.where((c) {
      final hay = '${c.message} ${c.aiSummary ?? ''}'.toLowerCase();
      return terms.any(hay.contains);
    }).toList();
    final hits = matched.isNotEmpty ? matched : commits;

    final sources = hits
        .map((c) => DailyBriefSource(
              sha: c.sha,
              message: c.message.split('\n').first,
              authorName: c.author.name,
              authorLogin: c.author.login,
              aiSummary: c.aiSummary,
              linkedTaskIds: c.linkedTaskIds,
            ))
        .toList();

    final answer = matched.isNotEmpty
        ? '根據今天的活動，有 ${matched.length} 個相關的 commit（見下方來源）。'
            '重點：${matched.first.aiSummary ?? matched.first.message}\n\n'
            '*(這是 fake backend 的示範回覆。)*'
        : '今天沒有和你問題直接相關的 commit；以下列出最近的提交作為參考。\n\n'
            '*(這是 fake backend 的示範回覆。)*';

    return DailyBriefReply(answer: answer, sources: sources);
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

  @override
  Future<String> requestDiscordFetch({
    required String repoId,
    required String date,
  }) async {
    // Mimic the real round-trip (bot backfill + digest flow) then emit a
    // digest so the Discord tab's refresh shows a result in fake mode.
    await Future.delayed(AppConfig.simulatedLatency * 4);
    FakeDiscordDigestRepository().emitDemoDigest(repoId, date);
    return 'fake-fetch-req-001';
  }

  @override
  Future<void> setDiscordStartDate({
    required String repoId,
    required String startDate,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency);
  }

  @override
  Future<void> setDiscordRange({
    required String repoId,
    required String startDate,
    required String endDate,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency);
  }

  @override
  Future<String> editDiscordDigest({
    required String repoId,
    required String date,
    required String instruction,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 3);
    final repo = FakeDiscordDigestRepository();
    final newMarkdown =
        '${DummyData.discordDigestMarkdown}\n\n> _AI 已依指令調整：「$instruction」（fake 示範）_';
    repo.applyEdit(repoId, date, markdown: newMarkdown);
    return newMarkdown;
  }

  @override
  Future<void> setDigestLock({
    required String repoId,
    required String date,
    required bool locked,
  }) async {
    await Future.delayed(AppConfig.simulatedLatency);
    FakeDiscordDigestRepository().applyEdit(repoId, date, locked: locked);
  }

  @override
  Future<DiscordChatReply> discordChat({
    required String repoId,
    required String question,
    List<DiscordChatTurn> history = const [],
  }) async {
    await Future.delayed(AppConfig.simulatedLatency * 3);

    final all = DummyData.discordMessages;

    // Keyword-match the demo messages the same way the backend tool does, then
    // group each match with one neighbor before/after as context — mirroring
    // the real callable's conversation-cluster shape.
    final terms = question
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9一-鿿]+'))
        .where((t) => t.length >= 2)
        .toSet();
    final matchIdxs = <int>[];
    for (var i = 0; i < all.length; i++) {
      final hay = all[i].content.toLowerCase();
      if (terms.any(hay.contains)) matchIdxs.add(i);
    }

    DiscordChatSource src(int i, {required bool isMatch}) {
      final m = all[i];
      return DiscordChatSource(
        messageId: m.id,
        channelId: m.channelId,
        authorName: m.authorName,
        content: m.content,
        timestamp: m.timestamp.toDate().toIso8601String(),
        isMatch: isMatch,
      );
    }

    final snippets = <DiscordChatSnippet>[];
    final hasMatch = matchIdxs.isNotEmpty;
    if (hasMatch) {
      // Build up to two clusters around the first matches; include one neighbor
      // before/after each match for context.
      for (final i in matchIdxs.take(2)) {
        final idxs = <int>{
          if (i - 1 >= 0) i - 1,
          i,
          if (i + 1 < all.length) i + 1,
        }.toList()
          ..sort();
        snippets.add(DiscordChatSnippet(
          channelId: all[i].channelId,
          messages: [for (final j in idxs) src(j, isMatch: j == i)],
        ));
      }
    } else {
      // Nothing matched: show the last ~3 messages as plain context.
      final start = all.length > 3 ? all.length - 3 : 0;
      snippets.add(DiscordChatSnippet(
        channelId: all.isNotEmpty ? all[start].channelId : '',
        messages: [
          for (var j = start; j < all.length; j++) src(j, isMatch: false),
        ],
      ));
    }

    final answer = !hasMatch
        ? '我在這個 repo 的 Discord 訊息裡找不到相關內容。'
        : '根據團隊的 Discord 聊天，以下幾段對話和你的問題相關。詳見下方可滑動的相關對話。\n\n'
            '*(這是 fake backend 的示範回覆。)*';

    return DiscordChatReply(answer: answer, snippets: snippets);
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
