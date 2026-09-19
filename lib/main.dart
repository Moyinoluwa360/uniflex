import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'shared/config/env_config.dart';
import 'shared/services/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EnvConfig.load();

  // Restores any persisted session synchronously once this completes —
  // AuthGate reads Supabase.instance.client.auth.currentSession right
  // after, no extra "wait for session" step needed.
  await Supabase.initialize(
    url: EnvConfig.supabaseUrl,
    publishableKey: EnvConfig.supabaseAnonKey,
  );

  // Phase 6: Firebase Cloud Messaging.
  // The placeholder google-services.json keeps the build green until the
  // real config file is dropped in — Firebase.initializeApp() will fail
  // gracefully and push notifications simply won't work until then.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationService.init();
  } catch (e) {
    // Firebase not yet configured — non-fatal, app continues without push.
    debugPrint('[Firebase] init skipped: $e');
  }

  runApp(const ProviderScope(child: UniflexApp()));
}
