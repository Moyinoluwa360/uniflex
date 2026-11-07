import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore_for_file: use_build_context_synchronously

/// Handles Firebase Cloud Messaging initialisation and local notification
/// display. Call [NotificationService.init] once from main() after Firebase
/// has been initialised.
///
/// The service:
///   1. Requests notification permission.
///   2. Gets the FCM token and stores it in `profiles.fcm_token` via RPC.
///   3. Configures flutter_local_notifications for foreground messages.
///   4. Listens for token refreshes and updates the DB.
///   5. Handles notification taps (background + terminated) and stores the
///      payload in [_pendingNavigation] for the active shell to consume.
///   6. Clears the FCM token on sign-out so a logged-out device stops
///      receiving pushes for the previous user.
class NotificationService {
  NotificationService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();

  /// Payload from the most recent notification tap (push OR the local
  /// banner shown while the app is open). A [ValueNotifier] so a shell that
  /// is already on screen — the app was only backgrounded — reacts to a
  /// tap immediately; a shell that mounts later (cold start) reads the
  /// value once via [consumePendingNavigation].
  ///
  /// Keys (all strings): `type`, `notification_id`, `order_id`,
  /// `group_id`, `conversation_id`.
  static final ValueNotifier<Map<String, dynamic>?> pendingNavigation =
      ValueNotifier<Map<String, dynamic>?>(null);

  static const _androidChannel = AndroidNotificationChannel(
    'uniflex_high',
    'Uniflex Notifications',
    description: 'Order updates, delivery alerts, and rewards',
    importance: Importance.high,
  );

  /// Initialise FCM, local notifications, and permission request.
  /// Safe to call even when Firebase is not fully configured (placeholder
  /// google-services.json); failures are caught and logged silently.
  static Future<void> init() async {
    try {
      // Request permission (iOS; Android 13+ also needs this)
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // Configure local notifications plugin
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        // Tapping the in-app banner behaves exactly like tapping a push.
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload == null || payload.isEmpty) return;
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map && decoded.isNotEmpty) {
              pendingNavigation.value = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        },
      );

      // Create the high-importance channel on Android
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      // Store token in DB. On iOS the FCM token only exists once Apple has
      // handed the app its APNs token, so wait briefly for that first. If it
      // still is not there (or getToken throws), carry on: the listeners
      // below must still be registered, and onTokenRefresh delivers the
      // token as soon as it exists.
      try {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          for (var i = 0;
              i < 20 && await _messaging.getAPNSToken() == null;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        final token = await _messaging.getToken();
        if (token != null) await _storeToken(token);
      } catch (e) {
        debugPrint('[NotificationService] token fetch deferred: $e');
      }

      // Update token on refresh.
      _messaging.onTokenRefresh.listen(_storeToken);

      // Show local notification when app is in foreground.
      FirebaseMessaging.onMessage.listen(_showLocalNotification);

      // Tap from background (app suspended but not killed).
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // Tap from terminated state (cold start).
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

      // Clear FCM token when user signs out so this device stops receiving
      // pushes for the previous user's account.
      Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedOut) {
          _clearToken();
          // A tap meant for the previous account must not open anything
          // for whoever signs in next on this device.
          pendingNavigation.value = null;
        }
      });
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  /// Returns and clears any pending navigation payload from a notification tap.
  /// Call once from the shell's initState (via postFrameCallback).
  static Map<String, dynamic>? consumePendingNavigation() {
    final nav = pendingNavigation.value;
    pendingNavigation.value = null;
    return nav;
  }

  static void _handleTap(RemoteMessage message) {
    if (message.data.isNotEmpty) {
      pendingNavigation.value = Map<String, dynamic>.from(message.data);
    }
  }

  static Future<void> _clearToken() async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      // Set token to null so this device no longer receives pushes.
      await client.rpc('store_fcm_token', params: {'p_token': null});
    } catch (e) {
      debugPrint('[NotificationService] clear token error: $e');
    }
  }

  static Future<void> _storeToken(String token) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client.rpc('store_fcm_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('[NotificationService] store token error: $e');
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await showLocal(notification.title, notification.body, data: message.data);
  }

  /// Shows the in-app banner for a push that arrived while the app is
  /// open. It is only a banner: the notification row already exists in the
  /// inbox (the server wrote it), so nothing is stored here.
  static Future<void> showLocal(
    String? title,
    String? body, {
    Map<String, dynamic>? data,
  }) async {
    if (title == null && body == null) return;
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
        payload: (data == null || data.isEmpty) ? null : jsonEncode(data),
      );
    } catch (e) {
      debugPrint('[NotificationService] showLocal error: $e');
    }
  }
}

/// Background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM background] ${message.messageId}');
}
