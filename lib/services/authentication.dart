import 'package:firebase_auth/firebase_auth.dart';

import '../repositories/user_repo.dart';

// GitSync sign-in flow: Firebase Auth via the GitHub provider. After sign-in
// we grab the OAuth access token and persist it to
// `users/{uid}.githubAccessToken`.
//
// Default scopes come from the OAuth app configuration; we additionally
// request `repo` (read/write issues/PRs/webhooks) and `read:user` via
// `provider.addScope`.
class AuthenticationService {
  AuthenticationService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final UserRepository _userRepository;

  // Consumed by the StreamBuilder<bool> in `main.dart`.
  Stream<bool> authStateChanges() =>
      _firebaseAuth.idTokenChanges().map((user) => user != null);

  User? get currentUser => _firebaseAuth.currentUser;
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  // ---- GitHub OAuth ------------------------------------------------------

  Future<String?> logInWithGitHub() async {
    final provider = GithubAuthProvider()
      ..addScope('repo')
      ..addScope('read:user');

    final cred = await _firebaseAuth.signInWithProvider(provider);
    final user = cred.user;
    if (user == null) return null;

    // The GitHub OAuth access token (used for the GitHub REST API) lives in
    // the OAuthCredential we get back from `signInWithProvider`.
    final accessToken = (cred.credential as OAuthCredential?)?.accessToken;

    // Persist the user (including GitHub login + access token).
    await _userRepository.upsertUserFromAuth(
      userId: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      avatarUrl: user.photoURL ?? '',
      // GitHub login lives on `additionalUserInfo.username`.
      githubLogin: cred.additionalUserInfo?.username ?? '',
      // TODO(security): encrypt with Cloud KMS before production
      // (ARCHITECTURE.md §6.1).
      githubAccessToken: accessToken,
    );

    return user.uid;
  }

  Future<void> logOut() async {
    await _firebaseAuth.signOut();
  }
}
