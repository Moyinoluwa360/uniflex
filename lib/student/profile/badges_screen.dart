import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../services/student_providers.dart';

/// Badges / achievements screen. Shows earned badges prominently and
/// unearned ones greyed-out so students know what to aim for.
class BadgesScreen extends ConsumerWidget {
  const BadgesScreen({super.key});

  // All possible badges ordered by desirability
  static const _allCodes = [
    'first_order',
    'ten_orders',
    'fifty_orders',
    'gifter',
    'silver_tier',
    'gold_tier',
    'platinum_tier',
    'birthday_bonus',
  ];

  /// Referral badges are not shown to students any more (Pack 4C): referral
  /// is handled through Admin, so nothing on the student side talks about
  /// referral counts or goals.
  static const _hiddenCodes = {'first_referral', 'ten_referrals'};

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final badgesAsync = ref.watch(userAchievementsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'My Badges'),
      body: badgesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (allEarned) {
          final earned =
              allEarned.where((a) => !_hiddenCodes.contains(a.code)).toList();
          final earnedCodes = earned.map((a) => a.code).toSet();
          final earnedCount = earnedCodes.length;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.screenGutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress summary
                      SizedBox(
                        width: double.infinity,
                        child: AppCard(
                          child: Row(
                            children: [
                              Icon(AppIcons.trophy, color: c.textSecondary),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  '$earnedCount / ${_allCodes.length} badges earned',
                                  style: AppTypography.body(c)
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (earned.isNotEmpty) ...[
                        const AppSectionLabel('Earned'),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: earned
                              .map((a) => _BadgeChip(
                                    name: a.name,
                                    description: a.description,
                                    iconName: a.iconName,
                                    earned: true,
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      const AppSectionLabel('In progress'),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),

              // Unearned badges grid
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  0,
                  AppSpacing.screenGutter,
                  AppSpacing.xl,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 1.3,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final code = _allCodes[i];
                      if (earnedCodes.contains(code)) return null;

                      // Look up display info from earned list (fallback to code)
                      final info = _badgeInfo[code];
                      return _UnearnedBadgeTile(
                        name: info?['name'] ?? code,
                        description: info?['description'] ?? '',
                      );
                    },
                    childCount: _allCodes.length,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _badgeInfo = <String, Map<String, String>>{
    'first_order': {
      'name': 'First Bite',
      'description': 'Place your first order'
    },
    'ten_orders': {'name': 'Regular', 'description': 'Place 10 orders'},
    'fifty_orders': {'name': 'Super Regular', 'description': 'Place 50 orders'},
    'gifter': {'name': 'Gifter', 'description': 'Send your first food gift'},
    'silver_tier': {
      'name': 'Silver Member',
      'description': 'Reach Silver tier (₦5,000+)'
    },
    'gold_tier': {
      'name': 'Gold Member',
      'description': 'Reach Gold tier (₦20,000+)'
    },
    'platinum_tier': {
      'name': 'Platinum Member',
      'description': 'Reach Platinum tier (₦50,000+)'
    },
    'birthday_bonus': {
      'name': 'Birthday Blessings',
      'description': 'Receive a birthday reward'
    },
  };
}

class _BadgeChip extends StatelessWidget {
  const _BadgeChip({
    required this.name,
    required this.description,
    required this.iconName,
    required this.earned,
  });
  final String name;
  final String description;
  final String iconName;
  final bool earned;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: description,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: earned ? c.brand : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.trophy,
                size: 16, color: earned ? c.brandText : c.textTertiary),
            const SizedBox(width: 4),
            Text(
              name,
              style: AppTypography.caption(c).copyWith(
                color: earned ? c.textPrimary : c.textTertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnearnedBadgeTile extends StatelessWidget {
  const _UnearnedBadgeTile({
    required this.name,
    required this.description,
  });
  final String name;
  final String description;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(AppIcons.lock, size: 24, color: c.textTertiary),
          const SizedBox(height: 4),
          Text(
            name,
            style: AppTypography.caption(c).copyWith(
              color: c.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            description,
            style: AppTypography.caption(c).copyWith(fontSize: 10.5),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
