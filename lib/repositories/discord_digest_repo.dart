import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/app_config.dart';
import '../models/discord_digest.dart';
import 'fake/fake_discord_digest_repo.dart';
import 'firestore_paths.dart';

abstract class DiscordDigestRepository {
  factory DiscordDigestRepository() => AppConfig.useFakeBackend
      ? FakeDiscordDigestRepository()
      : _LiveDiscordDigestRepository();

  /// Streams the digest doc for [date] (YYYY-MM-DD); emits null until the
  /// backend has produced one for that day.
  Stream<DiscordDigest?> streamDigest(String repoId, String date);
}

// NOTE: `discordDigests` is write-blocked for clients — only Cloud Functions
// (the digest flow) writes it.
class _LiveDiscordDigestRepository implements DiscordDigestRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  @override
  Stream<DiscordDigest?> streamDigest(String repoId, String date) {
    return _db
        .doc('${FirestorePaths.discordDigests(repoId)}/$date')
        .snapshots()
        .map((snap) => snap.exists
            ? DiscordDigest.fromMap(snap.data()!, snap.id)
            : null);
  }
}
