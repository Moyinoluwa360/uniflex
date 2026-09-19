import 'package:flutter/material.dart';

import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'dashboard/rider_dashboard_screen.dart';
import 'history/delivery_history_screen.dart';
import 'pool/job_pool_screen.dart';
import 'profile/rider_profile_screen.dart';

/// Root of the Rider experience. Owns its own navigation stack — no
/// screen here ever imports from lib/student/ or lib/admin/.
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
          screen: RiderDashboardScreen(),
        ),
        AppNavTab(
          label: 'Jobs',
          icon: Icons.inbox_outlined,
          selectedIcon: Icons.inbox,
          screen: JobPoolScreen(),
        ),
        AppNavTab(
          label: 'History',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history,
          screen: DeliveryHistoryScreen(),
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
