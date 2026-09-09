import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'user_role.dart';

/// The signed-in user's role, or `null` when nobody is signed in.
///
/// PHASE 0 NOTE — this is a mock. There is no real authentication yet:
/// [RoleRouter] just reads whatever role is in this provider. Phase 1
/// (Onboarding & Auth) replaces the write side of this with a real sign-in
/// flow (Supabase auth, OTP, etc.) that sets this provider on success —
/// the read side (RoleRouter watching it) does not need to change.
final currentUserRoleProvider = StateProvider<UserRole?>((ref) => null);
