import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import 'firestore_paths.dart';

class UserRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _timeout = Duration(seconds: 10);

  // ---- Read --------------------------------------------------------------

  Stream<AppUser?> streamUser(String userId) {
    return _db.doc(FirestorePaths.user(userId)).snapshots().map((snap) {
      final data = snap.data();
      if (data == null) return null;
      return AppUser.fromMap(data, snap.id);
    });
  }

  Future<AppUser?> getUser(String userId) async {
    final snap =
        await _db.doc(FirestorePaths.user(userId)).get().timeout(_timeout);
    final data = snap.data();
    if (data == null) return null;
    return AppUser.fromMap(data, snap.id);
  }

  // ---- Write -------------------------------------------------------------

  // Called on first sign-in; merges if the doc exists, otherwise creates it.
  // NOTE: `githubAccessToken` must already be encrypted (Cloud KMS) before
  // being passed in for production builds.
  Future<void> upsertUserFromAuth({
    required String userId,
    required String name,
    required String email,
    required String avatarUrl,
    required String githubLogin,
    String? githubAccessToken,
  }) async {
    final ref = _db.doc(FirestorePaths.user(userId));
    final map = <String, dynamic>{
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'githubLogin': githubLogin,
      if (githubAccessToken != null) 'githubAccessToken': githubAccessToken,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await ref.set(map, SetOptions(merge: true)).timeout(_timeout);
  }

  Future<void> updateFcmToken(String userId, String token) async {
    await _db
        .doc(FirestorePaths.user(userId))
        .update({'fcmToken': token}).timeout(_timeout);
  }

  Future<void> updateDiscordUserId(String userId, String discordUserId) async {
    await _db.doc(FirestorePaths.user(userId)).update({
      'discordUserId': discordUserId,
    }).timeout(_timeout);
  }
}
