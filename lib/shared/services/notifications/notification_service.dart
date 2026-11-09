import 'dart:async';
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
///   2. Gets the FCM token and registers this phone for the signed-in user
///      (`register_push_token`) — at launch, on every sign-in, and whenever
///      the token changes.
///   3. Configures flutter_local_notifications for foreground messages.
///   4. Listens for token refreshes and updates the DB.
///   5. Handles notification taps (background + terminated) and stores the
///      payload in [_pendingNavigation] for the active shell to consume.
///   6. Unregisters this phone on sign-out ([unregisterDevice], called by
///      `AuthService.signOut` while the session is still valid) so a
///      logged-out device stops receiving pushes for the previous user.
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
      // Configure local notifications plugin
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // Permission is requested once, by Firebase Messaging (below), so the
      // two plugins never race to show the iOS prompt.
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
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

      _ready = true;

      // Register this phone whenever the token changes, and whenever
      // someone signs in. The app usually launches signed OUT, so the
      // launch-time token fetch alone would never reach the server.
      _messaging.onTokenRefresh.listen((t) {
        _token = t;
        unawaited(_register());
      });
      Supabase.instance.client.auth.onAuthStateChange.listen((event) {
        switch (event.event) {
          case AuthChangeEvent.signedIn:
          case AuthChangeEvent.initialSession:
          case AuthChangeEvent.tokenRefreshed:
            unawaited(_register());
          case AuthChangeEvent.signedOut:
            _registeredKey = null;
            // A tap meant for the previous account must not open anything
            // for whoever signs in next on this device.
            pendingNavigation.value = null;
          default:
            break;
        }
      });

      // Show local notification when app is in foreground.
      FirebaseMessaging.onMessage.listen(_showLocalNotification);

      // Tap from background (app suspended but not killed).
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // Tap from terminated state (cold start).
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);

      // Permission prompt + token fetch can take seconds (iOS waits for
      // Apple's APNs token): never hold up the app's first frame for it.
      unawaited(_fetchTokenAndRegister());
    } catch (e) {
      debugPrint('[NotificationService] init error: $e');
    }
  }

  static bool _ready = false;

  /// This phone's current FCM token, once known.
  static String? _token;

  /// `userId|token` last registered successfully — stops repeat calls.
  static String? _registeredKey;

  /// Asks for permission, then gets the FCM token (retrying while Apple /
  /// Google hand it over) and registers it for whoever is signed in.
  static Future<void> _fetchTokenAndRegister() async {
    try {
      // iOS + Android 13+ permission prompt.
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[NotificationService] permission request failed: $e');
    }

    // On iOS the FCM token only exists once Apple has given the app its APNs
    // token, which can take a while on first launch — keep trying instead of
    // giving up after one attempt.
    for (var attempt = 0; attempt < 12 && _token == null; attempt++) {
      try {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
          for (var i = 0;
              i < 10 && await _messaging.getAPNSToken() == null;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }
        _token = await _messaging.getToken();
      } catch (e) {
        debugPrint('[NotificationService] token fetch retry $attempt: $e');
      }
      if (_token == null) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    await _register();
  }

  /// Registers this phone for the signed-in user. A no-op until both a token
  /// and a session exist, and when this exact pair is already registered.
  static Future<void> _register() async {
    final token = _token;
    if (!_ready || token == null) return;
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      final key = '$uid|$token';
      if (_registeredKey == key) return;
      final platform = (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
          ? 'ios'
          : 'android';
      try {
        await client.rpc('register_push_token',
            params: {'p_token': token, 'p_platform': platform});
      } catch (_) {
        // Server not updated yet: the old single-token call still works.
        await client.rpc('store_fcm_token', params: {'p_token': token});
      }
      _registeredKey = key;
    } catch (e) {
      debugPrint('[NotificationService] register token error: $e');
    }
  }

  /// Stops pushes for the current user on THIS phone. Call it BEFORE the
  /// session ends — the server only accepts it from a signed-in user.
  /// Never throws and never waits long: signing out must always work.
  static Future<void> unregisterDevice() async {
    final token = _token;
    if (!_ready || token == null) return;
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      await client
          .rpc('unregister_push_token', params: {'p_token': token})
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[NotificationService] unregister error: $e');
    }
    _registeredKey = null;
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
