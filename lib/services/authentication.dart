import 'package:firebase_auth/firebase_auth.dart';

import '../config/app_config.dart';
import '../repositories/user_repo.dart';
import 'fake/fake_authentication.dart';

/// Sign-in / sign-out for the app.
///
/// LIVE: Firebase Auth with the GitHub provider. After sign-in we grab the
/// OAuth access token and persist it to `users/{uid}.githubAccessToken`.
///
/// FAKE: auto-signs in as `DummyData.demoUserId`. Useful while
/// `Authentication → Sign-in method → GitHub` has not been enabled in the
/// Firebase Console yet.
///
/// TODO(handoff to E module — GitHub integration owner):
/// before flipping `AppConfig.defaultBackend` to `Backend.live`, you must:
///   1. Create a GitHub OAuth App at https://github.com/settings/developers
///   2. Enable GitHub provider in Firebase Console → Authentication →
///      Sign-in method → paste Client ID + Client Secret
///   3. Add the Firebase callback URL to the GitHub OAuth App's
///      Authorization callback URL field
///   4. Confirm `logInWithGitHub()` returns the OAuth access token via
///      `(cred.credential as OAuthCredential?)?.accessToken`
abstract class AuthenticationService {
  factory AuthenticationService() => AppConfig.useFakeBackend
      ? FakeAuthenticationService()
      : _LiveAuthenticationService();

  Stream<bool> authStateChanges();
  String? get currentUid;
  Future<String?> logInWithGitHub();
  Future<void> logOut();
}

class _LiveAuthenticationService implements AuthenticationService {
  _LiveAuthenticationService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final UserRepository _userRepository;

  @override
  Stream<bool> authStateChanges() =>
      _firebaseAuth.idTokenChanges().map((user) => user != null);

  @override
  String? get currentUid => _firebaseAuth.currentUser?.uid;

  @override
  Future<String?> logInWithGitHub() async {
    final provider = GithubAuthProvider()
      ..addScope('repo')
      ..addScope('read:user');

    final cred = await _firebaseAuth.signInWithProvider(provider);
    final user = cred.user;
    if (user == null) return null;

    final accessToken = (cred.credential as OAuthCredential?)?.accessToken;

    await _userRepository.upsertUserFromAuth(
      userId: user.uid,
      name: user.displayName ?? '',
      email: user.email ?? '',
      avatarUrl: user.photoURL ?? '',
      githubLogin: cred.additionalUserInfo?.username ?? '',
      // TODO(security): encrypt with Cloud KMS before production
      // (ARCHITECTURE.md §6.1).
      githubAccessToken: accessToken,
    );

    return user.uid;
  }

  @override
  Future<void> logOut() async {
    await _firebaseAuth.signOut();
  }
}
