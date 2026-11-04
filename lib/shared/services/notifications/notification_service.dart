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

  /// Payload from the most recent notification tap. Consumed once by the
  /// shell's initState via [consumePendingNavigation].
  static Map<String, dynamic>? _pendingNavigation;

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
      );

      // Create the high-importance channel on Android
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      // Store token in DB.
      final token = await _messaging.getToken();
      if (token != null) await _storeToken(token);

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
        }
      });
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  /// Returns and clears any pending navigation payload from a notification tap.
  /// Call once from the shell's initState (via postFrameCallback).
  static Map<String, dynamic>? consumePendingNavigation() {
    final nav = _pendingNavigation;
    _pendingNavigation = null;
    return nav;
  }

  static void _handleTap(RemoteMessage message) {
    if (message.data.isNotEmpty) {
      _pendingNavigation = Map<String, dynamic>.from(message.data);
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
    await showLocal(notification.title, notification.body);
  }

  /// Shows a local (foreground) notification banner. Used directly by
  /// Section 12's order-status-change listener (see StudentShell) so a
  /// status update from Supabase Realtime is surfaced immediately while
  /// the app is open, without waiting on an FCM push round-trip.
  static Future<void> showLocal(String? title, String? body) async {
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
