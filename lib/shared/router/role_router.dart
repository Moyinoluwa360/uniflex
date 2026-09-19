import 'package:flutter/material.dart';

import '../../admin/admin_shell.dart';
import '../../rider/rider_shell.dart';
import '../../student/student_shell.dart';
import '../services/auth/user_role.dart';

/// Swaps in exactly one of [StudentShell], [RiderShell], or [AdminShell] —
/// never more than one, never a mix. Each shell is a fully separate widget
/// tree / navigation stack; they must not import or route into each
/// other's screens — the only things they share are the theme, core
/// services, and the widgets under lib/shared/. If you find yourself
/// wanting a student screen to push a rider screen, that's a sign the
/// role boundary is being violated.
///
/// [role] is resolved by [AuthGate] from the signed-in account's
/// `profiles.role` — this widget only does the switch, it does not read
/// auth state itself. See auth_gate.dart for how a person gets here (and
/// how logout takes them back out).
class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key, required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    switch (role) {
      case UserRole.student:
        return const StudentShell();
      case UserRole.rider:
        return const RiderShell();
      case UserRole.admin:
        return const AdminShell();
    }
  }
}
