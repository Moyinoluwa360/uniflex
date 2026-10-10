import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to the values loaded from `.env` (see `.env.example` at the
/// project root for the full list of keys). Call [EnvConfig.load] once in
/// `main()` before `runApp`.
///
/// Every getter here returns an empty string until a real `.env` is filled
/// in — Phase 0 ships with no real backend, so these are all placeholders
/// by design. Later phases should read config through this class rather
/// than calling `dotenv.env[...]` directly, so there's one place that
/// knows every key the app depends on.
abstract final class EnvConfig {
  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // No .env present (e.g. a fresh checkout before copying
      // .env.example). Fall back to empty values rather than crashing —
      // the app should still boot and show mocked data.
      dotenv.testLoad(fileInput: '');
    }
  }

  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get paystackPublicKey =>
      dotenv.env['PAYSTACK_PUBLIC_KEY'] ?? '';
  static String get firebaseApiKey => dotenv.env['FIREBASE_API_KEY'] ?? '';
  static String get firebaseProjectId =>
      dotenv.env['FIREBASE_PROJECT_ID'] ?? '';
  static String get googleMapsApiKey =>
      dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
}
