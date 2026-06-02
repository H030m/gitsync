import '../../data/dummy_data.dart';
import '../../models/discord_digest.dart';
import '../discord_digest_repo.dart';
import '_replay_state.dart';

/// Fake digest repo. Starts empty (no digest) and only emits once
/// [emitDemoDigest] is called — which the fake `requestDiscordFetch` does to
/// mimic the real backend writing a `discordDigests/{date}` doc after a
/// refresh. This keeps the refresh button meaningful in fake mode.
class FakeDiscordDigestRepository implements DiscordDigestRepository {
  factory FakeDiscordDigestRepository() => _instance;
  FakeDiscordDigestRepository._internal();
  static final FakeDiscordDigestRepository _instance =
      FakeDiscordDigestRepository._internal();

  // Keyed by "repoId|date" so each day has its own replayable state.
  final Map<String, ReplayState<DiscordDigest?>> _byKey = {};

  String _key(String repoId, String date) => '$repoId|$date';

  ReplayState<DiscordDigest?> _state(String repoId, String date) => _byKey
      .putIfAbsent(_key(repoId, date), () => ReplayState<DiscordDigest?>(null));

  @override
  Stream<DiscordDigest?> streamDigest(String repoId, String date) =>
      _state(repoId, date).stream;

  /// Simulates the backend producing a digest for [date] (called by the fake
  /// FunctionsService after a refresh request settles).
  void emitDemoDigest(String repoId, String date) {
    _state(repoId, date).update(
      DiscordDigest(
        date: date,
        markdown: DummyData.discordDigestMarkdown,
        messageCount: DummyData.discordMessages.length,
      ),
    );
  }
}
