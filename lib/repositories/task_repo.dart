import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/task.dart';
import 'firestore_paths.dart';

class TaskRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

  Stream<List<Task>> streamTasks(String repoId) {
    return _db
        .collection(FirestorePaths.tasks(repoId))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Task.fromMap(d.data(), d.id))
            .toList());
  }

  Stream<Task?> streamTask(String repoId, String taskId) {
    return _db
        .doc('${FirestorePaths.tasks(repoId)}/$taskId')
        .snapshots()
        .map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return Task.fromMap(data, snap.id);
    });
  }

  Future<String> addTask(String repoId, Task task) async {
    final map = task.toMap()
      ..['createdAt'] = FieldValue.serverTimestamp()
      ..['updatedAt'] = FieldValue.serverTimestamp();
    final ref = await _db
        .collection(FirestorePaths.tasks(repoId))
        .add(map)
        .timeout(_timeout);
    return ref.id;
  }

  Future<void> updateStatus(
    String repoId,
    String taskId,
    TaskStatus status,
  ) async {
    await _db.doc('${FirestorePaths.tasks(repoId)}/$taskId').update({
      'status': status.wire,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  Future<void> assignTo(
    String repoId,
    String taskId,
    String? assigneeId,
  ) async {
    await _db.doc('${FirestorePaths.tasks(repoId)}/$taskId').update({
      'assigneeId': assigneeId,
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  Future<void> deleteTask(String repoId, String taskId) async {
    await _db
        .doc('${FirestorePaths.tasks(repoId)}/$taskId')
        .delete()
        .timeout(_timeout);
  }

  // Find downstream tasks: who depends on me. Uses `array-contains`; requires
  // the composite index defined in ARCHITECTURE.md §5.6.
  Future<List<Task>> getDependentsOf(String repoId, String taskId) async {
    final snap = await _db
        .collection(FirestorePaths.tasks(repoId))
        .where('dependsOn', arrayContains: taskId)
        .get()
        .timeout(_timeout);
    return snap.docs.map((d) => Task.fromMap(d.data(), d.id)).toList();
  }
}
