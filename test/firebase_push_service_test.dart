import 'package:capstone_app/services/firebase_push_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FirebasePushService payload parsing', () {
    test('prefers notification payload values when available', () {
      final message = RemoteMessage(
        notification: const RemoteNotification(
          title: 'New task',
          body: 'A task was assigned to you',
        ),
        data: {'id': '42', 'type': 'task'},
      );

      final record = FirebasePushService.buildNotificationRecord(message);

      expect(record['title'], 'New task');
      expect(record['body'], 'A task was assigned to you');
      expect(record['id'], '42');
    });

    test('falls back to data payload values when notification is absent', () {
      final message = RemoteMessage(
        data: {
          'title': 'Reminder',
          'body': 'Please review the report',
          'id': '99',
        },
      );

      final record = FirebasePushService.buildNotificationRecord(message);

      expect(record['title'], 'Reminder');
      expect(record['body'], 'Please review the report');
      expect(record['id'], '99');
    });
  });
}
