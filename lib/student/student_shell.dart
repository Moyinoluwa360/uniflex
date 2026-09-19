import 'package:flutter/material.dart';

import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/student_home_screen.dart';
import 'orders/orders_screen.dart';
import 'profile/student_profile_screen.dart';
import 'wallet/wallet_screen.dart';

/// Root of the Student experience. Phase 2 adds Orders and Wallet tabs.
/// No screen in here should import from lib/rider/ or lib/admin/.
class StudentShell extends StatelessWidget {
  const StudentShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBottomNavShell(
      tabs: [
        AppNavTab(
          label: 'Home',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          screen: StudentHomeScreen(),
        ),
        AppNavTab(
          label: 'Orders',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          screen: OrdersScreen(),
        ),
        AppNavTab(
          label: 'Wallet',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: WalletScreen(),
        ),
        AppNavTab(
          label: 'Profile',
          icon: Icons.person_outline,
          selectedIcon: Icons.person,
          screen: StudentProfileScreen(),
        ),
      ],
    );
  }
}
