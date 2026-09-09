import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_shell.dart';
import '../../rider/rider_shell.dart';
import '../../student/student_shell.dart';
import '../services/auth/session_provider.dart';
import '../services/auth/user_role.dart';
import 'mock_role_select_screen.dart';

/// The single entry point that decides which of the three top-level app
/// experiences a person sees. This is the whole "role router" pattern:
///
///   1. [currentUserRoleProvider] holds the signed-in user's role (or
///      `null` if nobody is signed in).
///   2. This widget watches that provider and swaps in exactly one of
///      [StudentShell], [RiderShell], or [AdminShell] — never more than
///      one, never a mix.
///   3. Each shell is a fully separate widget tree / navigation stack.
///      They must not import or route into each other's screens — the
///      only things they share are the theme, core services, and the
///      widgets under lib/shared/. If you find yourself wanting a
///      student screen to push a rider screen, that's a sign the role
///      boundary is being violated.
///
/// PHASE 0 NOTE: there is no real auth yet, so when [currentUserRoleProvider]
/// is null this shows [MockRoleSelectScreen] — a dev-only stand-in that
/// lets you set the role directly to prove the router works. Phase 1
/// replaces that screen with real onboarding/sign-in; the switch below
/// does not need to change.
class RoleRouter extends ConsumerWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);

    switch (role) {
      case null:
        return const MockRoleSelectScreen();
      case UserRole.student:
        return const StudentShell();
      case UserRole.rider:
        return const RiderShell();
      case UserRole.admin:
        return const AdminShell();
    }
  }
}
