import 'package:supabase_flutter/supabase_flutter.dart';

/// Thin wrapper around Supabase Auth. Screens depend on this (via
/// [authServiceProvider] in auth_providers.dart) rather than reaching for
/// `Supabase.instance.client.auth` directly, so sign-in/out logic has one
/// place to live and tests can substitute a fake.
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  /// Fires on sign-in, sign-out, and token refresh — used by
  /// [authStateChangesProvider] to keep the rest of the app in sync with
  /// the persisted session.
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  /// Step One of student sign-up. Supabase project's "Confirm email"
  /// setting must be off (see supabase/schema.sql) — this app's own
  /// verification gate is the Termii phone OTP, not an email link.
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signUp(email: email, password: password);
  }

  /// Used by the shared Login screen for Students, Riders, and Admins
  /// alike — which shell a person lands on is decided by their
  /// `profiles.role`, not by which button they pressed to sign in.
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();
}
