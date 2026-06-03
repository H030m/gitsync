import 'package:cloud_firestore/cloud_firestore.dart';

// Mirrors Firestore `apps/gitsync/repos/{repoId}/discordDigests/{date}`,
// the AI-generated markdown summary of one day's Discord chat. Written by
// `discordDailyDigestFlow` (see functions/src/flows/discordDailyDigest.ts)
// after the bot backfills the day's messages.

class DiscordDigest {
  final String date; // YYYY-MM-DD (also the doc id)
  final String markdown;
  final int messageCount;

  /// When true the digest is pinned: no backend path (auto-regen or AI edit)
  /// will change it. Toggled via `setDigestLock`.
  final bool locked;
  Timestamp? _generatedAt;
  Timestamp get generatedAt => _generatedAt ?? Timestamp.now();

  DiscordDigest({
    required this.date,
    required this.markdown,
    required this.messageCount,
    this.locked = false,
    Timestamp? generatedAt,
  }) : _generatedAt = generatedAt;

  factory DiscordDigest.fromMap(Map<String, dynamic> map, String id) {
    return DiscordDigest(
      date: map['date'] as String? ?? id,
      markdown: map['markdown'] as String? ?? '',
      messageCount: map['messageCount'] as int? ?? 0,
      locked: map['locked'] as bool? ?? false,
      generatedAt: map['generatedAt'] as Timestamp?,
    );
  }
}
