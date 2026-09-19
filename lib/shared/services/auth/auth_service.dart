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

  // ── Forgot password (post-testing fixes, Section 3) ────────────────────
  //
  // OTP-based rather than link-based, to match the existing pattern in this
  // app (Termii phone OTP for sign-up verification) and to avoid needing
  // any deep-link/native URL-scheme setup. Supabase's recovery email must
  // have its template edited in the Dashboard to include `{{ .Token }}` so
  // it contains a 6-digit code, not just a link — see README.md.

  /// Sends a password-reset email containing a 6-digit recovery code.
  Future<void> sendPasswordResetOtp(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  /// Verifies the 6-digit code from the reset email. On success this
  /// establishes a recovery session, after which [updatePassword] can be
  /// called to actually set the new password.
  Future<void> verifyPasswordResetOtp({
    required String email,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.recovery,
      email: email,
      token: token,
    );
  }

  /// Sets a new password on the current (recovery) session. AuthGate picks
  /// up the now-valid session on its own — this never navigates.
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }
}
