import 'package:cloud_firestore/cloud_firestore.dart';

// Mirrors Firestore `apps/gitsync/repos/{repoId}/dailyReports/{YYYY-MM-DD}`.

class MemberContribution {
  final int tasksDone;
  final int commits;

  const MemberContribution({this.tasksDone = 0, this.commits = 0});

  factory MemberContribution.fromMap(Map<String, dynamic> map) =>
      MemberContribution(
        tasksDone: (map['tasksDone'] as num?)?.toInt() ?? 0,
        commits: (map['commits'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'tasksDone': tasksDone,
        'commits': commits,
      };
}

class DailyReport {
  final String date; // Doc id is the date as YYYY-MM-DD.
  final String repoId;
  final String summary;
  final List<String> completedTaskIds;
  final Map<String, MemberContribution> memberContributions;
  final Timestamp? generatedAt;

  const DailyReport({
    required this.date,
    required this.repoId,
    required this.summary,
    this.completedTaskIds = const [],
    this.memberContributions = const {},
    this.generatedAt,
  });

  factory DailyReport.fromMap(Map<String, dynamic> map, String id) {
    final raw = Map<String, dynamic>.from(
      map['memberContributions'] as Map? ?? {},
    );
    return DailyReport(
      date: id,
      repoId: map['repoId'] as String? ?? '',
      summary: map['summary'] as String? ?? '',
      completedTaskIds:
          List<String>.from(map['completedTasks'] as List? ?? []),
      memberContributions: raw.map(
        (k, v) => MapEntry(
          k,
          MemberContribution.fromMap(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      generatedAt: map['generatedAt'] as Timestamp?,
    );
  }
}
