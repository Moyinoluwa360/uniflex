import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
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
    'first_referral',
    'ten_referrals',
    'gifter',
    'silver_tier',
    'gold_tier',
    'platinum_tier',
    'birthday_bonus',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final badgesAsync = ref.watch(userAchievementsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Badges')),
      body: badgesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
        data: (earned) {
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.emerald.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.circular(AppRadius.card),
                          border: Border.all(
                              color:
                                  AppColors.emerald.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.emoji_events,
                                color: AppColors.emerald),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                '$earnedCount / ${_allCodes.length} badges earned',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: AppColors.emerald,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (earned.isNotEmpty) ...[
                        Text('Earned', style: theme.textTheme.titleSmall),
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
                                    theme: theme,
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                      ],
                      Text('In progress', style: theme.textTheme.titleSmall),
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
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                        theme: theme,
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
    'fifty_orders': {
      'name': 'Super Regular',
      'description': 'Place 50 orders'
    },
    'first_referral': {
      'name': 'Connector',
      'description': 'Refer your first friend'
    },
    'ten_referrals': {
      'name': 'Ambassador',
      'description': 'Refer 10 friends'
    },
    'gifter': {
      'name': 'Gifter',
      'description': 'Send your first food gift'
    },
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
    required this.theme,
  });
  final String name;
  final String description;
  final String iconName;
  final bool earned;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: description,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: earned
              ? AppColors.emerald.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: earned
                ? AppColors.emerald.withValues(alpha: 0.4)
                : theme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.emoji_events,
                size: 16,
                color:
                    earned ? AppColors.emerald : theme.colorScheme.outline),
            const SizedBox(width: 4),
            Text(
              name,
              style: theme.textTheme.labelSmall?.copyWith(
                color: earned
                    ? AppColors.emerald
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
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
    required this.theme,
  });
  final String name;
  final String description;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline,
              size: 24,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 4),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.3),
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
