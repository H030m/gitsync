import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/member.dart';
import 'firestore_paths.dart';

// NOTE: `members` is write-blocked for clients; only Cloud Functions update
// counters (e.g. `onTaskCreated`, `onPRMerged`).
class MemberRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<Member>> streamMembers(String repoId) {
    return _db
        .collection(FirestorePaths.members(repoId))
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Member.fromMap(d.data(), d.id)).toList());
  }
}
