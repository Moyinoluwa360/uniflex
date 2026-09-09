import 'package:flutter/material.dart';

import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/rider_home_screen.dart';
import 'profile/rider_profile_screen.dart';

/// Root of the Rider experience. Owns its own navigation stack — no
/// screen in here should ever import from lib/student/ or lib/admin/.
/// Add new Rider-only screens as new files under lib/rider/, and wire
/// new top-level tabs into the `tabs` list below.
class RiderShell extends StatelessWidget {
  const RiderShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.two_wheeler_outlined,
          selectedIcon: Icons.two_wheeler,
          screen: RiderHomeScreen(),
        ),
        AppNavTab(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: RiderProfileScreen(),
        ),
      ],
    );
  }
}
