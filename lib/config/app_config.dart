// Central runtime configuration. Read via `--dart-define` flags or fall back
// to compile-time defaults below.
//
// Examples:
//   flutter run --dart-define=BACKEND=fake    # in-memory dummy data, no Firebase
//   flutter run --dart-define=BACKEND=live    # real Firestore + Auth + Functions
//   flutter run                                # uses [defaultBackend] below
//
// Why this exists: teammates can clone the repo and run the app immediately
// without having to set up Firebase, OAuth, OpenAI keys, etc. The fake mode
// uses canned data from `lib/data/dummy_data.dart` and short artificial
// latencies so the UI feels real.
class AppConfig {
  AppConfig._();

  // ---- Backend selection ------------------------------------------------

  /// What you'll get with a plain `flutter run` (no dart-define overrides).
  /// Flip this to `Backend.live` once your local Firebase + OAuth is fully set up.
  static const Backend defaultBackend = Backend.fake;

  static Backend get backend {
    const raw = String.fromEnvironment('BACKEND', defaultValue: '');
    return switch (raw.toLowerCase()) {
      'fake' || 'mock' || 'dummy' => Backend.fake,
      'live' || 'real' || 'prod' => Backend.live,
      _ => defaultBackend,
    };
  }

  static bool get useFakeBackend => backend == Backend.fake;

  // ---- Target: cloud (real Firebase) vs local emulator ------------------

  /// Which Firebase backend a *live* build talks to. One switch for the whole
  /// system — keep it in sync with the Discord bot's `TARGET` in
  /// `discord-bot/.env` so the app and bot hit the same place:
  ///   --dart-define=TARGET=cloud      → the real gitsync-645b3 cloud (default)
  ///   --dart-define=TARGET=emulator   → the local Firebase Emulator Suite
  /// Ignored in fake mode (no Firebase at all).
  static const String _target =
      String.fromEnvironment('TARGET', defaultValue: 'cloud');

  /// True when [backend] is live AND TARGET=emulator.
  static bool get useEmulator => _target.toLowerCase() == 'emulator';

  /// Host the emulator is reachable at. `localhost` works for web / desktop /
  /// iOS simulator; for the Android AVD use
  /// `--dart-define=EMULATOR_HOST=10.0.2.2`.
  static const String emulatorHost =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

  // ---- FCM web --------------------------------------------------------

  /// VAPID public key for FCM web push. Obtain from Firebase Console →
  /// Cloud Messaging → Web Push certificates → Generate key pair, then run
  /// with `--dart-define=FCM_VAPID_KEY=...`. Empty (default) = web token
  /// fetch skipped with a clear console warning; mobile FCM is unaffected.
  static const String fcmVapidKey =
      String.fromEnvironment('FCM_VAPID_KEY', defaultValue: '');

  // ---- GitHub OAuth (manual connect flow) -----------------------------

  /// GitHub OAuth App **client_id** (public — it travels in the authorize URL).
  /// Must match the OAuth App whose **client_secret** is set as the Cloud
  /// Function secret `GITHUB_OAUTH_CLIENT_SECRET` (and the backend
  /// `GITHUB_OAUTH_CLIENT_ID`). Override per build with
  /// `--dart-define=GITHUB_OAUTH_CLIENT_ID=...`. The secret is NEVER here.
  static const String githubOAuthClientId = String.fromEnvironment(
    'GITHUB_OAUTH_CLIENT_ID',
    defaultValue: 'Ov23liwPB1WZPu35k5hT',
  );

  /// Custom URL scheme for the OAuth redirect capture (`flutter_web_auth_2`).
  /// The GitHub OAuth App's "Authorization callback URL" must be
  /// `${githubOAuthRedirectUri}` (i.e. `gitsync://oauth/github`).
  static const String githubOAuthCallbackScheme = 'gitsync';

  /// The full redirect URI registered on the GitHub OAuth App. Sent to the
  /// backend so its token exchange uses the identical `redirect_uri`.
  static const String githubOAuthRedirectUri = 'gitsync://oauth/github';

  /// Scopes the connect flow requests (must match what backend consumers need).
  static const List<String> githubOAuthScopes = ['repo', 'read:user'];

  // ---- Fake-mode tuning -------------------------------------------------

  /// Artificial delay added to fake repository / service calls so streams
  /// don't all resolve in the same microtask (helps you SEE loading
  /// indicators during UI development).
  static Duration get simulatedLatency =>
      const Duration(milliseconds: 250);

  /// When in fake mode, the demo user is auto-signed-in on launch so we
  /// skip the sign-in screen. Set to false to test the sign-in flow itself.
  static const bool autoSignInDemoUser = true;
}

enum Backend { fake, live }
