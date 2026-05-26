import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/discord_message.dart';
import 'firestore_paths.dart';

// NOTE: `discordMessages` is write-blocked for clients (the forwarder bot
// pushes through `discordMessageIngest` instead).
class DiscordMessageRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<DiscordMessage>> streamRecent(String repoId, {int limit = 100}) {
    return _db
        .collection(FirestorePaths.discordMessages(repoId))
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => DiscordMessage.fromMap(d.data(), d.id))
            .toList());
  }
}
