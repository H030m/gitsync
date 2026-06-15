import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../repositories/user_repo.dart';
import 'local_notifications.dart';
import 'navigation.dart';

// FCM wiring. Three responsibilities:
//   1. Pull the FCM token and persist it to `users/{uid}.fcmToken`.
//   2. Handle foreground notifications (logged; the in-app assignment banner in
//      RepoShell covers the foreground "you were assigned" UX via Firestore).
//   3. Route taps on notifications to the matching task via the data payload
//      ({ type, repoId, taskId } — see tools/notify.ts), falling back to /notify.
//
// NOTE: must only be initialized in live (Firebase) mode — FirebaseMessaging
// requires an initialized Firebase app, which fake-backend mode skips.
class PushMessagingService {
  PushMessagingService({UserRepository? userRepository})
      : _userRepository = userRepository ?? UserRepository();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final UserRepository _userRepository;
  NavigationService? _navigation;
  bool _initialized = false;

  Future<bool> initialize({
    required String userId,
    NavigationService? navigation,
  }) async {
    if (_initialized) return true;
    _navigation = navigation;

    final settings = await _fcm.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      // Permission denied — leave uninitialized so a later sign-in can retry.
      return false;
    }
    _initialized = true;

    // Local-notification channel so foreground FCM can surface as a real OS
    // notification (Android otherwise swallows them while the app is open).
    // Tapping a foreground notification routes via its JSON payload, the same
    // way a backgrounded tap routes via RemoteMessage.data.
    await LocalNotificationsService.instance.init(
      onTap: (payload) => _routeFromData(decodeNotificationPayload(payload)),
    );

    // Foreground messages: redraw as a visible local notification, in addition
    // to the in-app banner (RepoShell, Firestore listener on assigneeId == me).
    FirebaseMessaging.onMessage.listen((m) {
      debugPrint('[FCM foreground] ${m.notification?.title}');
      final n = m.notification;
      final title = n?.title ?? m.data['title'] ?? 'GitSync';
      final body = n?.body ?? m.data['body'] ?? '';
      LocalNotificationsService.instance.show(
        title: title,
        body: body,
        // Carry the full routing payload (repoId + taskId + type) so a tap can
        // deep-link — m.data['taskId'] alone lacks the repoId to build the route.
        payload: jsonEncode(m.data),
      );
    });

    // Tap while the app was backgrounded.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // Background messages need a top-level handler (see bottom of file).
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

    // Cold start: the app was launched by tapping a notification.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleTap(initial);

    String? token;
    if (kIsWeb) {
      final vapidKey = AppConfig.fcmVapidKey;
      if (vapidKey.isEmpty) {
        debugPrint(
          '[FCM web] FCM_VAPID_KEY not set — token fetch skipped. '
          'See docs/SETUP.md (or README) for how to obtain one.',
        );
      } else {
        token = await _fcm.getToken(vapidKey: vapidKey);
      }
    } else {
      token = await _fcm.getToken();
    }
    if (token != null) {
      await _userRepository.updateFcmToken(userId, token);
    }
    _fcm.onTokenRefresh.listen((t) {
      _userRepository.updateFcmToken(userId, t);
    });
    return true;
  }

  // Deep-link a backgrounded / cold-start tap via its RemoteMessage.data.
  void _handleTap(RemoteMessage m) => _routeFromData(m.data);

  // Single routing decision shared by background taps (RemoteMessage.data) and
  // foreground taps (the local notification's decoded JSON payload): a valid
  // repoId + taskId deep-links to the task, anything else lands on /notify.
  void _routeFromData(Map<String, dynamic>? data) {
    final nav = _navigation;
    if (nav == null) return;
    final route = taskRouteFromData(data);
    if (route != null) {
      nav.goTaskDetails(route.repoId, route.taskId);
    } else {
      nav.goNotify();
    }
  }
}

/// Parses a notification data map into a task deep-link target, or null when it
/// lacks a usable repoId + taskId. Pure + side-effect free for unit testing.
@visibleForTesting
({String repoId, String taskId})? taskRouteFromData(Map<String, dynamic>? data) {
  if (data == null) return null;
  final repoId = data['repoId'];
  final taskId = data['taskId'];
  if (repoId is String &&
      repoId.isNotEmpty &&
      taskId is String &&
      taskId.isNotEmpty) {
    return (repoId: repoId, taskId: taskId);
  }
  return null;
}

/// Decodes a local-notification JSON string payload back into a data map.
/// Returns null for a null/empty/non-object/malformed payload (caller then
/// falls back to /notify). Pure + side-effect free for unit testing.
@visibleForTesting
Map<String, dynamic>? decodeNotificationPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Background messages only log here; FCM already shows the system tray
  // notification.
  debugPrint('[FCM background] ${message.messageId}');
}
