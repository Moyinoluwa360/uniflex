import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';
import '../otp/phone_otp_service.dart';
import '../profile/profile_service.dart';
import '../supabase/supabase_providers.dart';
import 'auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.watch(supabaseClientProvider));
});

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ref.watch(supabaseClientProvider));
});

final phoneOtpServiceProvider = Provider<PhoneOtpService>((ref) {
  return PhoneOtpService(ref.watch(supabaseClientProvider));
});

/// Fires on sign-in, sign-out, and token refresh. [currentProfileProvider]
/// watches this so the whole app — [AuthGate] in particular — reacts to a
/// login or logout without any screen having to navigate manually.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authServiceProvider).onAuthStateChange;
});

/// The signed-in user's profile row, or `null` when nobody is signed in.
/// This is the single source of truth [AuthGate] uses to decide between
/// the splash/login flow, resuming Step Two, and the correct role shell —
/// see auth_gate.dart.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  // Rebuild whenever the auth state changes, not just once at app start.
  ref.watch(authStateChangesProvider);

  final session = ref.watch(authServiceProvider).currentSession;
  if (session == null) return null;

  return ref.watch(profileServiceProvider).fetchProfile(session.user.id);
});
