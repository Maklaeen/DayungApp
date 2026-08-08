import 'package:capstone_app/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'buildNotificationRecordFromRemoteMessage uses notification payload values',
    () {
      final message = RemoteMessage(
        messageId: 'msg-1',
        notification: const RemoteNotification(
          title: 'New announcement',
          body: 'The committee posted an update',
        ),
        data: {'type': 'announcement', 'announcement_id': '42'},
      );

      final record =
          PushNotificationService.buildNotificationRecordFromRemoteMessage(
            message,
          );

      expect(record['title'], 'New announcement');
      expect(record['body'], 'The committee posted an update');
      expect(record['data']['type'], 'announcement');
      expect(record['id'], 'msg-1');
    },
  );
}
