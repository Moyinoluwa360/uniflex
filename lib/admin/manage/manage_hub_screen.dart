import 'package:flutter/material.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../advertisements/advertisements_screen.dart';
import '../around_categories/around_categories_screen.dart';
import '../referrals/referral_codes_screen.dart';
import '../riders/rider_management_screen.dart';
import '../vendors/vendor_management_screen.dart';

/// Post-testing fixes, Section 8 — a single "Manage" bottom-nav entry
/// that opens this hub, which then branches into each management area.
/// New admin capabilities (Rider management in Section 7, Around
/// categories in Section 9) land as entries here instead of each getting
/// its own bottom-nav tab, so the nav bar doesn't grow every phase.
class ManageHubScreen extends StatelessWidget {
  const ManageHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Manage'),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: const [
          _ManageEntry(
            icon: Icons.storefront_outlined,
            title: 'Manage Vendors',
            subtitle: 'Partner vendors and their menus',
            screen: VendorManagementScreen(),
          ),
          SizedBox(height: AppSpacing.cardGap),
          _ManageEntry(
            icon: Icons.two_wheeler_outlined,
            title: 'Manage Riders',
            subtitle: 'Add, remove, and activate Rider accounts',
            screen: RiderManagementScreen(),
          ),
          SizedBox(height: AppSpacing.cardGap),
          _ManageEntry(
            icon: Icons.explore_outlined,
            title: 'Around Categories',
            subtitle: 'The service categories students can request',
            screen: AroundCategoriesScreen(),
          ),
          SizedBox(height: AppSpacing.cardGap),
          _ManageEntry(
            icon: Icons.confirmation_number_outlined,
            title: 'Referral Codes',
            subtitle: 'Mint codes, allocate them, and track signups',
            screen: ReferralCodesScreen(),
          ),
          SizedBox(height: AppSpacing.cardGap),
          _ManageEntry(
            icon: Icons.campaign_outlined,
            title: 'Advertisements',
            subtitle: 'Banners on the student home page',
            screen: AdvertisementsScreen(),
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
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget screen;

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
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
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
