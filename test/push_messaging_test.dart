import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitsync/services/push_messaging.dart';

void main() {
  group('taskRouteFromData', () {
    test('returns the deep-link target for a valid task_ready payload', () {
      final route = taskRouteFromData(
        {'type': 'task_ready', 'repoId': 'r1', 'taskId': 't1'},
      );
      expect(route, isNotNull);
      expect(route!.repoId, 'r1');
      expect(route.taskId, 't1');
    });

    test('returns null when data is null', () {
      expect(taskRouteFromData(null), isNull);
    });

    test('returns null when repoId or taskId is missing', () {
      expect(taskRouteFromData({'repoId': 'r1'}), isNull);
      expect(taskRouteFromData({'taskId': 't1'}), isNull);
      expect(taskRouteFromData(const {}), isNull);
    });

    test('returns null when repoId or taskId is empty', () {
      expect(taskRouteFromData({'repoId': '', 'taskId': 't1'}), isNull);
      expect(taskRouteFromData({'repoId': 'r1', 'taskId': ''}), isNull);
    });
  });

  group('decodeNotificationPayload', () {
    test('round-trips a JSON-encoded data map', () {
      final data = {'type': 'task_ready', 'repoId': 'r1', 'taskId': 't1'};
      final decoded = decodeNotificationPayload(jsonEncode(data));
      expect(decoded, isNotNull);
      expect(taskRouteFromData(decoded), isNotNull);
      expect(taskRouteFromData(decoded)!.taskId, 't1');
    });

    test('returns null for null / empty / malformed / non-object payloads', () {
      expect(decodeNotificationPayload(null), isNull);
      expect(decodeNotificationPayload(''), isNull);
      expect(decodeNotificationPayload('not json {'), isNull);
      expect(decodeNotificationPayload('"a string"'), isNull);
      expect(decodeNotificationPayload('[1,2,3]'), isNull);
    });

    test('a bare taskId payload (old format) decodes to no route', () {
      // Pre-fix foreground payload was the raw taskId string, not JSON.
      expect(taskRouteFromData(decodeNotificationPayload('t1')), isNull);
    });
  });
}
