import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/pull_request.dart';
import 'firestore_paths.dart';

// NOTE: `pullRequests` is write-blocked for clients; Cloud Functions only.
class PullRequestRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<PullRequest>> streamRecent(String repoId, {int limit = 50}) {
    return _db
        .collection(FirestorePaths.pullRequests(repoId))
        .orderBy('mergedAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => PullRequest.fromMap(d.data(), d.id)).toList());
  }
}
