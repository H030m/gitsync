import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

import '../config/app_config.dart';
import '../repositories/user_repo.dart';
import 'fake/fake_authentication.dart';
import 'functions_service.dart';

/// Sign-in / sign-out for the app.
///
/// LIVE: Firebase Auth with the GitHub provider. After sign-in we grab the
/// OAuth access token (scopes `repo` + `read:user`) and persist it to
/// `users/{uid}.githubAccessToken`. The live flow is implemented; it only
/// needs the one-time GitHub OAuth App + Firebase Console enablement
/// documented in `docs/SETUP.md §B.4`.
///
/// FAKE: auto-signs in as `DummyData.demoUserId`. Useful while
/// `Authentication → Sign-in method → GitHub` has not been enabled in the
/// Firebase Console yet.
abstract class AuthenticationService {
  factory AuthenticationService() => AppConfig.useFakeBackend
      ? FakeAuthenticationService()
      : _LiveAuthenticationService();

  Stream<bool> authStateChanges();
  String? get currentUid;
  Future<String?> logInWithGitHub();
  Future<void> logOut();

  /// Runs the manual GitHub OAuth authorization-code flow to (re)obtain a valid
  /// `users/{uid}.githubAccessToken`. Needed on Android, where
  /// `signInWithProvider` can't surface the OAuth token (task 06-16), and as the
  /// "Reconnect GitHub" path on any platform when the stored token goes stale.
  ///
  /// Opens GitHub's authorize page in an in-app browser tab, captures the
  /// `?code=...` redirect, then calls the `exchangeGitHubCode` Cloud Function
  /// (which holds the client_secret) to swap the code for a token and persist it.
  /// Returns true on success; throws on cancel / mismatch / backend failure.
  Future<bool> connectGitHub();
}

class _LiveAuthenticationService implements AuthenticationService {
  _LiveAuthenticationService({
    UserRepository? userRepository,
    FunctionsService? functionsService,
  })  : _userRepository = userRepository ?? UserRepository(),
        _functions = functionsService ?? FunctionsService();

  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final UserRepository _userRepository;
  final FunctionsService _functions;

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

    // On web, firebase_auth surfaces the provider OAuth access token reliably
    // through the popup flow (`signInWithPopup`); `signInWithProvider` is the
    // mobile/desktop path. Both return a `UserCredential` whose `.credential`
    // is the `OAuthCredential` carrying `accessToken`.
    // NOTE: end-to-end web token retrieval needs a manual e2e run once the
    // GitHub provider is enabled (docs/SETUP.md §B.4).
    final cred = kIsWeb
        ? await _firebaseAuth.signInWithPopup(provider)
        : await _firebaseAuth.signInWithProvider(provider);
    final user = cred.user;
    if (user == null) return null;

    // On Android `signInWithProvider` hands back a base `AuthCredential`
    // (not an `OAuthCredential`), so a hard `as OAuthCredential?` cast throws
    // "type 'AuthCredential' is not a subtype of OAuthCredential?". Guard with
    // `is` so the token is read when present and degrades to null otherwise.
    final credential = cred.credential;
    final accessToken =
        credential is OAuthCredential ? credential.accessToken : null;

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
  Future<bool> connectGitHub() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw StateError('Must be signed in before connecting GitHub.');
    }

    // CSRF state — echoed back by GitHub and verified on the redirect.
    final state = _randomState();
    final scope = AppConfig.githubOAuthScopes.join(' ');
    final authorizeUrl = Uri.https('github.com', '/login/oauth/authorize', {
      'client_id': AppConfig.githubOAuthClientId,
      'redirect_uri': AppConfig.githubOAuthRedirectUri,
      'scope': scope,
      'state': state,
      // Force the account picker so a re-connect can switch/refresh the grant.
      'allow_signup': 'false',
    });

    // Opens the system browser tab and resolves with the captured redirect URL.
    final result = await FlutterWebAuth2.authenticate(
      url: authorizeUrl.toString(),
      callbackUrlScheme: AppConfig.githubOAuthCallbackScheme,
    );

    final returned = Uri.parse(result);
    final code = returned.queryParameters['code'];
    final returnedState = returned.queryParameters['state'];
    if (returnedState != state) {
      throw StateError('GitHub OAuth state mismatch (possible CSRF).');
    }
    if (code == null || code.isEmpty) {
      final err = returned.queryParameters['error_description'] ??
          returned.queryParameters['error'] ??
          'no authorization code returned';
      throw StateError('GitHub authorization failed: $err');
    }

    // Server-side exchange (client_secret stays in the Cloud Function) writes
    // the token to users/{uid}.githubAccessToken.
    await _functions.exchangeGitHubCode(
      code: code,
      redirectUri: AppConfig.githubOAuthRedirectUri,
    );
    return true;
  }

  static String _randomState() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  Future<void> logOut() async {
    await _firebaseAuth.signOut();
  }
}
