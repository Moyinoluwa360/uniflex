import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/services/auth/auth_providers.dart';
import '../shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'dashboard/admin_dashboard_screen.dart';
import 'kitchen/kitchen_queue_screen.dart';
import 'manage/manage_hub_screen.dart';
import 'menu/menu_management_screen.dart';
import 'profile/admin_profile_screen.dart';
import 'scheduled/admin_scheduled_orders_screen.dart';

/// Root of the Admin experience. Reads [currentProfileProvider] to
/// determine the admin tier and shows tabs accordingly:
///
/// - `kitchen_staff` → Queue + Profile only
/// - `super_admin` (or null, for backwards-compat) → Dashboard + Queue +
///   Menu + Manage + Profile
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
    label: 'Queue',
    icon: Icons.restaurant_menu_outlined,
    selectedIcon: Icons.restaurant_menu,
    screen: KitchenQueueScreen(),
  ),
  AppNavTab(
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    screen: AdminProfileScreen(),
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
    label: 'Queue',
    icon: Icons.restaurant_menu_outlined,
    selectedIcon: Icons.restaurant_menu,
    screen: KitchenQueueScreen(),
  ),
  AppNavTab(
    label: 'Scheduled',
    icon: Icons.schedule_outlined,
    selectedIcon: Icons.schedule,
    screen: AdminScheduledOrdersScreen(),
  ),
  AppNavTab(
    label: 'Menu',
    icon: Icons.menu_book_outlined,
    selectedIcon: Icons.menu_book,
    screen: MenuManagementScreen(),
  ),
  AppNavTab(
    label: 'Manage',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
    screen: ManageHubScreen(),
  ),
  AppNavTab(
    label: 'Profile',
    icon: Icons.person_outline,
    selectedIcon: Icons.person,
    screen: AdminProfileScreen(),
  ),
];
