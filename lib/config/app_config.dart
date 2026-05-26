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
