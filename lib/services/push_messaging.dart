import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../repositories/user_repo.dart';

// FCM wiring. Three responsibilities:
//   1. Pull the FCM token and persist it to `users/{uid}.fcmToken`.
//   2. Handle foreground notifications (show in-app banner or SnackBar).
//   3. Route taps on notifications to the `/notify` screen.
class PushMessagingService {
  PushMessagingService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final UserRepository _userRepository;

  Future<bool> initialize({required String userId}) async {
    final settings = await _fcm.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      return false;
    }

    // Foreground messages.
    FirebaseMessaging.onMessage.listen((m) {
      // Placeholder for in-app banner/SnackBar logic.
      debugPrint('[FCM foreground] ${m.notification?.title}');
    });

    // User tapped a notification while the app was suspended.
    FirebaseMessaging.onMessageOpenedApp.listen((m) {
      // Placeholder for payload-based navigation to task/daily.
      debugPrint('[FCM opened] ${m.data}');
    });

    // Background messages need a top-level handler (see bottom of file).
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    final token = await _fcm.getToken();
    if (token != null) {
      await _userRepository.updateFcmToken(userId, token);
    }
    _fcm.onTokenRefresh.listen((t) {
      _userRepository.updateFcmToken(userId, t);
    });
    return true;
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Background messages only log here; FCM already shows the system tray
  // notification.
  debugPrint('[FCM background] ${message.messageId}');
}
