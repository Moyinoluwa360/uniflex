import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/support/support_chat_service.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../advertisements/advertisements_screen.dart';
import '../errand_categories/errand_categories_screen.dart';
import '../delivery_settings/delivery_settings_screen.dart';
import '../menu/menu_management_screen.dart';
import '../profile/admin_profile_screen.dart';
import '../referrals/referral_codes_screen.dart';
import '../riders/rider_management_screen.dart';
import '../scheduled/admin_scheduled_orders_screen.dart';
import '../support/admin_support_inbox_screen.dart';
import '../vendors/vendor_management_screen.dart';

/// The "Manage" bottom-nav tab — a single hub that branches into every
/// admin management area. Menu, Vendors, Riders, Errand Categories,
/// Referral Codes, Advertisements, Scheduled Orders, Support, and Profile all
/// live here instead of cluttering the bottom nav bar.
class ManageHubScreen extends ConsumerWidget {
  const ManageHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(adminSupportUnreadProvider);
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Manage'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          const _ManageEntry(
            icon: Icons.menu_book_outlined,
            title: 'Menu',
            subtitle: 'Uniflex catalog items and categories',
            screen: MenuManagementScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.storefront_outlined,
            title: 'Manage Vendors',
            subtitle: 'Partner vendors and their menus',
            screen: VendorManagementScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.two_wheeler_outlined,
            title: 'Manage Riders',
            subtitle: 'Add, remove, and activate Rider accounts',
            screen: RiderManagementScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.explore_outlined,
            title: 'Errand Categories',
            subtitle: 'The service categories students can request',
            screen: ErrandCategoriesScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.schedule_outlined,
            title: 'Scheduled Orders',
            subtitle: 'Pre-orders with countdown timers',
            screen: AdminScheduledOrdersScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.confirmation_number_outlined,
            title: 'Referral Codes',
            subtitle: 'Mint codes, allocate them, and track signups',
            screen: ReferralCodesScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.local_shipping_outlined,
            title: 'Delivery Locations',
            subtitle: 'Named locations and delivery pricing',
            screen: DeliverySettingsScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.campaign_outlined,
            title: 'Advertisements',
            subtitle: 'Banners on the student home page',
            screen: AdvertisementsScreen(),
          ),
          const SizedBox(height: AppSpacing.cardGap),
          // Support chat — shows unread badge when students are waiting.
          _ManageEntry(
            icon: Icons.support_agent_outlined,
            title: 'Support',
            subtitle: 'Student messages and conversations',
            screen: const AdminSupportInboxScreen(),
            badgeCount: unread,
          ),
          const SizedBox(height: AppSpacing.cardGap),
          const _ManageEntry(
            icon: Icons.person_outline,
            title: 'Profile & Settings',
            subtitle: 'Your admin profile and logout',
            screen: AdminProfileScreen(),
          ),
        ],
      ),
    );
  }
}

class _ManageEntry extends StatelessWidget {
  const _ManageEntry({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.screen,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => screen),
      ),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Badge(
              isLabelVisible: badgeCount > 0,
              label: Text('$badgeCount'),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(icon, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
