import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/services/notifications/notification_service.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'home/student_home_screen.dart';
import 'notifications/notification_router.dart';
import 'ordering/cart_notice_listener.dart';
import 'orders/orders_screen.dart';
import 'profile/student_profile_screen.dart';
import 'wallet/wallet_screen.dart';

/// Root of the Student experience. No screen in here should import from
/// lib/rider/ or lib/admin/.
///
/// Notifications (Pack 4A): this shell no longer watches order streams to
/// fire local notifications — that only worked while the app was open and
/// produced duplicates next to the server's push. Every notification is now
/// written and pushed by the server; this shell only
///   * routes a tapped push / banner to the right screen (including a tap
///     that cold-started the app), and
///   * shows the one-time cart-expiry notice.
class StudentShell extends ConsumerStatefulWidget {
  const StudentShell({super.key});

  @override
  ConsumerState<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends ConsumerState<StudentShell> {
  @override
  void initState() {
    super.initState();
    NotificationService.pendingNavigation.addListener(_onPendingNavigation);
    // A tap that launched the app (cold start) was stored before this
    // shell existed.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPendingNavigation());
  }

  @override
  void dispose() {
    NotificationService.pendingNavigation.removeListener(_onPendingNavigation);
    super.dispose();
  }

  void _onPendingNavigation() {
    if (!mounted) return;
    final nav = NotificationService.consumePendingNavigation();
    if (nav == null) return;
    openNotificationTarget(context, ref, NotificationTarget.fromPayload(nav));
  }

  @override
  Widget build(BuildContext context) {
    return const CartNoticeListener(
      child: AppBottomNavShell(
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
      ),
    );
  }
}
