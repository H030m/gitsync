import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/repo.dart';
import 'firestore_paths.dart';

class RepoRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

  // Lists every repo the user is a member of (uses memberIds array-contains).
  Stream<List<Repo>> streamReposOfUser(String userId) {
    return _db
        .collection(FirestorePaths.repos)
        .where('memberIds', arrayContains: userId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Repo.fromMap(d.data(), d.id))
            .toList());
  }

  Stream<Repo?> streamRepo(String repoId) {
    return _db.doc(FirestorePaths.repo(repoId)).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return Repo.fromMap(data, snap.id);
    });
  }

  Future<Repo?> getRepo(String repoId) async {
    final snap = await _db
        .doc(FirestorePaths.repo(repoId))
        .get()
        .timeout(_timeout);
    final data = snap.data();
    if (data == null) return null;
    return Repo.fromMap(data, snap.id);
  }

  // Direct Firestore writes are insufficient for adding a repo (we need to
  // verify the GitHub repo and register a webhook). Use the `addRepo`
  // callable instead. This method is kept for admin metadata edits.
  Future<void> updateMetadata(String repoId, Map<String, dynamic> patch) async {
    await _db.doc(FirestorePaths.repo(repoId)).update(patch).timeout(_timeout);
  }
}
