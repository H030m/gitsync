import 'package:cloud_firestore/cloud_firestore.dart';

import '../config/app_config.dart';
import '../models/commit.dart';
import 'fake/fake_commit_repo.dart';
import 'firestore_paths.dart';

abstract class CommitRepository {
  factory CommitRepository() => AppConfig.useFakeBackend
      ? FakeCommitRepository()
      : _LiveCommitRepository();

  Stream<List<Commit>> streamRecent(String repoId, {int limit = 50});
  Stream<List<Commit>> streamCommitsForDay(String repoId, DateTime day);
  Future<Commit?> getCommit(String repoId, String sha);
}

// NOTE: The `commits` collection is write-blocked for clients (Firestore
// Rules set `allow write: if false`); only Cloud Functions may write to it.
class _LiveCommitRepository implements CommitRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

  @override
  Stream<List<Commit>> streamRecent(String repoId, {int limit = 50}) {
    return _db
        .collection(FirestorePaths.commits(repoId))
        .orderBy('committedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Commit.fromMap(d.data(), d.id)).toList());
  }

  @override
  Stream<List<Commit>> streamCommitsForDay(String repoId, DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _db
        .collection(FirestorePaths.commits(repoId))
        .where('committedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
            isLessThan: Timestamp.fromDate(end))
        .orderBy('committedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Commit.fromMap(d.data(), d.id)).toList());
  }

  @override
  Future<Commit?> getCommit(String repoId, String sha) async {
    final snap = await _db
        .doc('${FirestorePaths.commits(repoId)}/$sha')
        .get()
        .timeout(_timeout);
    final data = snap.data();
    if (data == null) return null;
    return Commit.fromMap(data, snap.id);
  }
}
