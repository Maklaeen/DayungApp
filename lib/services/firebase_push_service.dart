import 'dart:async';

import 'package:capstone_app/services/push_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FirebasePushService {
  FirebasePushService._();

  static final FirebasePushService instance = FirebasePushService._();

  static Map<String, dynamic> buildNotificationRecord(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    final id = message.data['id']?.toString();

    return {'id': id, 'title': title, 'body': body, 'data': message.data};
  }

  Future<void> initialize() async {
    if (kIsWeb) {
      return;
    }

    try {
      await Firebase.initializeApp();
      await _requestPermission();

      FirebaseMessaging.onMessage.listen((message) {
        final record = buildNotificationRecord(message);
        PushNotificationService.instance.showFromRecord(record);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint(
          '[FirebasePushService] onMessageOpenedApp: messageId=${message.messageId}, data=${message.data}',
        );
      });

      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        debugPrint('[FirebasePushService] FCM token retrieved: $token');
        await _saveTokenToSupabase(token);
      } else {
        debugPrint('[FirebasePushService] FCM token is null');
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        debugPrint('[FirebasePushService] FCM token refreshed: $newToken');
        await _saveTokenToSupabase(newToken);
      });
    } catch (error, stackTrace) {
      debugPrint('Firebase push initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _requestPermission() async {
    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('Push notification permission granted.');
    }
  }

  Future<void> _saveTokenToSupabase(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    try {
      await Supabase.instance.client.from('profiles').upsert({
        'id': user.id,
        'fcm_token': token,
      });
      debugPrint(
        '[FirebasePushService] Saved FCM token to Supabase for user ${user.id}',
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save FCM token: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }
}
