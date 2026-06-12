// Models for the unified "Ask GitSync" chat — the global repo-wide assistant
// reached from the FAB on every repo-shell tab. These are plain callable-payload
// shapes (no Firestore coupling); the chat flows through the `askRepo` callable.
//
// Sources reuse the existing per-tab shapes: commits are `DailyBriefSource`
// (the backend `DayCommit` shape) and Discord clusters are `DiscordChatSnippet`
// — so the sheet renders them with the same panels the Summary / Discord tabs
// already use.
import 'daily_brief.dart';
import 'discord_chat.dart';

/// One turn of the user <-> AI conversation. Sent back as history so follow-up
/// questions keep context.
class AskRepoTurn {
  /// `'user'` or `'assistant'`.
  final String role;
  final String content;

  /// Commits the AI surfaced for this turn (assistant turns only).
  final List<DailyBriefSource> commitSources;

  /// Discord conversation clusters the AI surfaced (assistant turns only).
  final List<DiscordChatSnippet> discordSources;

  /// When this turn was created on the client (for the bubble timestamp).
  final DateTime? createdAt;

  const AskRepoTurn({
    required this.role,
    required this.content,
    this.commitSources = const [],
    this.discordSources = const [],
    this.createdAt,
  });

  bool get isUser => role == 'user';

  bool get hasSources => commitSources.isNotEmpty || discordSources.isNotEmpty;

  /// Sent back to the backend as a prior turn (role + content only).
  Map<String, dynamic> toMap() => {'role': role, 'content': content};
}

/// The `askRepo` callable's response: the AI answer plus the commits and
/// Discord clusters it surfaced as cited sources.
class AskRepoReply {
  final String answer;
  final List<DailyBriefSource> commits;
  final List<DiscordChatSnippet> snippets;

  const AskRepoReply({
    required this.answer,
    this.commits = const [],
    this.snippets = const [],
  });

  factory AskRepoReply.fromMap(Map<String, dynamic> map) => AskRepoReply(
        answer: map['answer'] as String? ?? '',
        commits: (map['commits'] as List? ?? const [])
            .map((c) =>
                DailyBriefSource.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
        snippets: (map['snippets'] as List? ?? const [])
            .map((s) =>
                DiscordChatSnippet.fromMap(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );
}
