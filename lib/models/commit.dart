// ignore_for_file: prefer_initializing_formals

import 'package:cloud_firestore/cloud_firestore.dart';

// Mirrors Firestore `apps/gitsync/repos/{repoId}/commits/{commitSha}`.
// NOTE: The `messageEmbedding` (Vector) field is deliberately not mapped
// to the Flutter side — it is only consumed by backend vector search.

class CommitAuthor {
  final String login;
  final String name;
  final String email;

  const CommitAuthor({
    required this.login,
    required this.name,
    required this.email,
  });

  factory CommitAuthor.fromMap(Map<String, dynamic> map) => CommitAuthor(
        login: map['login'] as String? ?? '',
        name: map['name'] as String? ?? '',
        email: map['email'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'login': login,
        'name': name,
        'email': email,
      };
}

class Commit {
  final String sha;
  final String repoId;
  final String message;
  final CommitAuthor author;
  final String url;
  final List<String> filesChanged;
  final int additions;
  final int deletions;
  final List<String> linkedTaskIds;
  final String? aiSummary;
  Timestamp? _committedAt;
  Timestamp get committedAt => _committedAt ?? Timestamp.now();

  Commit({
    required this.sha,
    required this.repoId,
    required this.message,
    required this.author,
    required this.url,
    this.filesChanged = const [],
    this.additions = 0,
    this.deletions = 0,
    this.linkedTaskIds = const [],
    this.aiSummary,
    Timestamp? committedAt,
  }) : _committedAt = committedAt;

  Commit._({
    required this.sha,
    required this.repoId,
    required this.message,
    required this.author,
    required this.url,
    required this.filesChanged,
    required this.additions,
    required this.deletions,
    required this.linkedTaskIds,
    this.aiSummary,
    required Timestamp? committedAt,
  }) : _committedAt = committedAt;

  factory Commit.fromMap(Map<String, dynamic> map, String sha) {
    return Commit._(
      sha: sha,
      repoId: map['repoId'] as String? ?? '',
      message: map['message'] as String? ?? '',
      author: CommitAuthor.fromMap(
        Map<String, dynamic>.from(map['author'] as Map? ?? {}),
      ),
      url: map['url'] as String? ?? '',
      filesChanged: List<String>.from(map['filesChanged'] as List? ?? []),
      additions: (map['additions'] as num?)?.toInt() ?? 0,
      deletions: (map['deletions'] as num?)?.toInt() ?? 0,
      linkedTaskIds: List<String>.from(map['linkedTaskIds'] as List? ?? []),
      aiSummary: map['aiSummary'] as String?,
      committedAt: map['committedAt'] as Timestamp?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Commit && other.sha == sha);
  @override
  int get hashCode => sha.hashCode;
}
