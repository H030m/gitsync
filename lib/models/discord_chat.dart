// Models for the Discord AI chat feature. These are plain
// callable-payload shapes (no Firestore Timestamp coupling), since the chat
// flows entirely through the `discordChat` Cloud Functions callable.

/// One turn of the user <-> AI conversation, sent back to the backend as
/// history so follow-up questions keep context.
class DiscordChatTurn {
  /// `'user'` or `'assistant'`.
  final String role;
  final String content;

  /// Messages the AI surfaced for this turn (assistant turns only). Shown in
  /// the scrollable sources panel; not sent back to the backend.
  final List<DiscordChatSource> sources;

  /// When this turn was created on the client (for the bubble timestamp).
  /// Null only for transient placeholders.
  final DateTime? createdAt;

  const DiscordChatTurn({
    required this.role,
    required this.content,
    this.sources = const [],
    this.createdAt,
  });

  bool get isUser => role == 'user';

  Map<String, dynamic> toMap() => {'role': role, 'content': content};
}

/// A Discord message the AI cited, as returned by the callable.
class DiscordChatSource {
  final String messageId;
  final String channelId;
  final String authorName;
  final String content;

  /// ISO 8601 string, or null if the source had no timestamp.
  final String? timestamp;

  const DiscordChatSource({
    required this.messageId,
    required this.channelId,
    required this.authorName,
    required this.content,
    this.timestamp,
  });

  factory DiscordChatSource.fromMap(Map<String, dynamic> map) {
    return DiscordChatSource(
      messageId: map['messageId'] as String? ?? '',
      channelId: map['channelId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      content: map['content'] as String? ?? '',
      timestamp: map['timestamp'] as String?,
    );
  }
}

/// The callable's response: the AI answer plus the messages it surfaced.
class DiscordChatReply {
  final String answer;
  final List<DiscordChatSource> messages;

  const DiscordChatReply({required this.answer, required this.messages});

  factory DiscordChatReply.fromMap(Map<String, dynamic> map) {
    final raw = map['messages'] as List? ?? const [];
    return DiscordChatReply(
      answer: map['answer'] as String? ?? '',
      messages: raw
          .map((m) => DiscordChatSource.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList(),
    );
  }
}
