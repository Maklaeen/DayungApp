import 'dart:async';

import 'package:capstone_app/Members/top_notification.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef PushNotificationTapHandler = void Function(String? payload);

class _PendingInAppBanner {
  const _PendingInAppBanner({required this.title, required this.body});

  final String title;
  final String body;
}

class PushNotificationService {
  PushNotificationService._();

  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<AuthState>? _authSubscription;
  RealtimeChannel? _notificationsChannel;
  RealtimeChannel? _applicationChannel;
  bool _initialized = false;
  PushNotificationTapHandler? _onTap;
  GlobalKey<NavigatorState>? _navigatorKey;
  final List<_PendingInAppBanner> _pendingInAppBanners = [];
  bool _isFlushingPendingBanners = false;

  Future<void> initialize({
    required PushNotificationTapHandler onTap,
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    _navigatorKey = navigatorKey;
    if (kIsWeb) {
      _onTap = onTap;
      return;
    }

    if (_initialized) {
      _onTap = onTap;
      return;
    }

    try {
      _onTap = onTap;

      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      final initializationSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: (response) {
          _onTap?.call(response.payload);
        },
      );

      await _ensureAndroidChannel();
      await _requestPermissions();

      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((data) {
            if (data.event == AuthChangeEvent.signedIn ||
                data.event == AuthChangeEvent.initialSession ||
                data.event == AuthChangeEvent.tokenRefreshed) {
              if (data.session != null) _subscribeToRealtime();
            } else if (data.event == AuthChangeEvent.signedOut) {
              _unsubscribeRealtime();
            }
          });

      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('Push notification initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _ensureAndroidChannel() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      const channel = AndroidNotificationChannel(
        'dayung_notifications',
        'Dayung notifications',
        description: 'Notifications for Dayung updates',
        importance: Importance.max,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
    } catch (error, stackTrace) {
      debugPrint('Failed to create Android notification channel: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _requestPermissions() async {
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    } catch (error, stackTrace) {
      debugPrint('Notification permission request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _subscribeToRealtime() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      return;
    }

    _unsubscribeRealtime();

    _notificationsChannel = Supabase.instance.client.channel(
      'device_notifications_$userId',
    );
    _notificationsChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'recipient_id',
            value: userId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            await _showLocalNotification(record);
          },
        )
        .subscribe();

    _applicationChannel = Supabase.instance.client.channel(
      'device_application_notifications_$userId',
    );
    _applicationChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'dayung_application_notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'secretary_id',
            value: userId,
          ),
          callback: (payload) async {
            final record = payload.newRecord;
            await _showLocalNotification(record);
          },
        )
        .subscribe();
  }

  static Map<String, dynamic> buildNotificationRecordFromRemoteMessage(
    dynamic message,
  ) {
    final title = message.notification?.title ?? message.data['title'];
    final body = message.notification?.body ?? message.data['body'];
    final id = message.data['id']?.toString() ?? message.messageId;

    return {'id': id, 'title': title, 'body': body, 'data': message.data};
  }

  static String resolveTitle(Map<String, dynamic> record) {
    final title = (record['title'] ?? record['message'] ?? 'New notification')
        .toString()
        .trim();
    return title.isNotEmpty ? title : 'New notification';
  }

  static String resolveBody(Map<String, dynamic> record) {
    final body =
        (record['body'] ?? record['message'] ?? 'You have a new update')
            .toString()
            .trim();
    return body.isNotEmpty ? body : 'You have a new update';
  }

  Future<void> _showLocalNotification(Map<String, dynamic> record) async {
    final title = resolveTitle(record);
    final body = resolveBody(record);

    if (title.isEmpty && body.isEmpty) {
      return;
    }

    final notificationTitle = title.isNotEmpty ? title : 'New notification';
    final notificationBody = body.isNotEmpty ? body : 'You have a new update';
    final notificationId =
        ((record['id']?.toString().hashCode ?? 0).abs() % 1000000);

    // Show system tray notification
    final androidDetails = AndroidNotificationDetails(
      'dayung_notifications',
      'Dayung notifications',
      channelDescription: 'Notifications for Dayung updates',
      importance: Importance.max,
      priority: Priority.high,
      ticker: notificationBody,
      styleInformation: BigTextStyleInformation(notificationBody),
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      notificationId,
      notificationTitle,
      notificationBody,
      details,
      payload: 'open_notifications',
    );

    // Show in-app banner when app is in foreground
    _showInAppBanner(notificationTitle, notificationBody);
  }

  void _showInAppBanner(String title, String body) {
    _pendingInAppBanners.add(_PendingInAppBanner(title: title, body: body));
    _flushPendingInAppBanners();
  }

  void _flushPendingInAppBanners() {
    if (_isFlushingPendingBanners) {
      return;
    }

    _isFlushingPendingBanners = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey?.currentContext;
      if (context == null) {
        _isFlushingPendingBanners = false;
        if (_pendingInAppBanners.isNotEmpty) {
          _flushPendingInAppBanners();
        }
        return;
      }

      while (_pendingInAppBanners.isNotEmpty) {
        final pendingBanner = _pendingInAppBanners.removeAt(0);
        TopNotificationBanner.show(
          context,
          title: pendingBanner.title,
          message: pendingBanner.body,
          icon: Icons.notifications_active_rounded,
          backgroundColor: const Color(0xFF0D47A1),
        );
      }

      _isFlushingPendingBanners = false;
    });
  }

  /// Called by FirebasePushService for foreground and background FCM messages.
  Future<void> showFromRecord(Map<String, dynamic> record) async {
    await _showLocalNotification(record);
  }

  Future<void> handleRemoteMessage(dynamic message) async {
    final record = buildNotificationRecordFromRemoteMessage(message);
    await showFromRecord(record);
  }

  void _unsubscribeRealtime() {
    try {
      _notificationsChannel?.unsubscribe();
    } catch (_) {}
    try {
      _applicationChannel?.unsubscribe();
    } catch (_) {}
    _notificationsChannel = null;
    _applicationChannel = null;
  }

  Future<void> dispose() async {
    _unsubscribeRealtime();
    await _authSubscription?.cancel();
    _authSubscription = null;
    _initialized = false;
  }
}
