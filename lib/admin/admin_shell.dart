import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/services/auth/auth_providers.dart';
import '../shared/services/notifications/notification_service.dart';
import '../shared/services/support/support_chat_service.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'analytics/admin_analytics_screen.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'kitchen/kitchen_queue_screen.dart';
import 'manage/manage_hub_screen.dart';
import 'orders/admin_orders_screen.dart';
import 'support/admin_support_inbox_screen.dart';

/// Root of the Admin experience. Reads [currentProfileProvider] to
/// determine the admin tier and shows tabs accordingly:
///
/// - `kitchen_staff` → Orders (Queue) only
/// - `super_admin` (or null, for backwards-compat) → Dashboard + Orders +
///   Manage + Analytics
///
/// Profile, settings, and logout live under the Dashboard header
/// (super_admin) or a gear icon (kitchen_staff), not the bottom bar.
///
/// Owns its own navigation stack — no screen inside here should import
/// from lib/student/ or lib/rider/.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
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
    if (nav?['type'] == 'support') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AdminSupportInboxScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isKitchenStaff = profile?.isKitchenStaff ?? false;

    if (isKitchenStaff) {
      return const AppBottomNavShell(tabs: _kitchenStaffTabs);
    }

    // Manage tab is index 2 — show unread badge for support messages.
    final unread = ref.watch(adminSupportUnreadProvider);
    return AppBottomNavShell(
      tabs: _superAdminTabs,
      badgeCounts: [0, 0, unread, 0],
    );
  }
}

const _kitchenStaffTabs = [
  AppNavTab(
    label: 'Orders',
    icon: Icons.restaurant_menu_outlined,
    selectedIcon: Icons.restaurant_menu,
    screen: KitchenQueueScreen(),
  ),
];

const _superAdminTabs = [
  AppNavTab(
    label: 'Dashboard',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
    screen: AdminDashboardScreen(),
  ),
  AppNavTab(
    label: 'Orders',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
    screen: AdminOrdersScreen(),
  ),
  AppNavTab(
    label: 'Manage',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    screen: ManageHubScreen(),
  ),
  AppNavTab(
    label: 'Analytics',
    icon: Icons.bar_chart_outlined,
    selectedIcon: Icons.bar_chart,
    screen: AdminAnalyticsScreen(),
  ),
];
