import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/services/auth/auth_providers.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'analytics/admin_analytics_screen.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'kitchen/kitchen_queue_screen.dart';
import 'manage/manage_hub_screen.dart';

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
class AdminShell extends ConsumerWidget {
  const AdminShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(currentProfileProvider);
    final profile = profileAsync.valueOrNull;
    final isKitchenStaff = profile?.isKitchenStaff ?? false;

    final tabs = isKitchenStaff
        ? _kitchenStaffTabs
        : _superAdminTabs;

    return AppBottomNavShell(tabs: tabs);
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
    screen: KitchenQueueScreen(),
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
