import 'package:flutter/material.dart';

import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/admin_home_screen.dart';
import 'profile/admin_profile_screen.dart';

/// Root of the Admin experience — this also covers Kitchen Staff duties,
/// there is no separate kitchen login. Owns its own navigation stack — no
/// screen in here should ever import from lib/student/ or lib/rider/.
/// Add new Admin-only screens as new files under lib/admin/, and wire new
/// top-level tabs into the `tabs` list below.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          screen: AdminHomeScreen(),
        ),
        AppNavTab(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: AdminProfileScreen(),
        ),
      ],
    );
  }
}
