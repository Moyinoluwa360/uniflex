import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/profile.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../services/student_providers.dart';

/// Membership card — shows current tier, progress to next, perks list,
/// reward points balance, and order stats.
class MembershipCardScreen extends ConsumerWidget {
  const MembershipCardScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final statsAsync = ref.watch(studentStatsProvider);

    final tier = statsAsync.valueOrNull?['membership_tier'] as String? ??
        profile.membershipTier;
    final points =
        statsAsync.valueOrNull?['reward_points'] as int? ?? profile.rewardPoints;
    final spending = (statsAsync.valueOrNull?['lifetime_spending'] as num?)
            ?.toDouble() ??
        profile.lifetimeSpending;
    final totalOrders =
        statsAsync.valueOrNull?['total_orders'] as int? ?? profile.totalOrders;

    final tierColor = _tierColor(tier);
    final progress = _tierProgress(spending);
    final nextTier = _nextTier(tier);
    final spendToNext = _spendToNext(spending);

    return Scaffold(
      appBar: AppBar(title: const Text('Membership')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Membership card ─────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [tierColor, tierColor.withValues(alpha: 0.7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.card * 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tier,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: AppColors.pureWhite,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Icon(_tierIcon(tier),
                          color: AppColors.pureWhite.withValues(alpha: 0.8),
                          size: 36),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    profile.nickname ?? profile.fullName ?? '—',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.pureWhite.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CardStat(
                          label: 'Reward Points',
                          value: '$points',
                          theme: theme),
                      _CardStat(
                          label: 'Orders',
                          value: '$totalOrders',
                          theme: theme),
                      _CardStat(
                          label: 'Spent',
                          value: '₦${spending.toStringAsFixed(0)}',
                          theme: theme),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Progress to next tier ───────────────────────────────────
            if (nextTier != null) ...[
              Text('Progress to $nextTier',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(tierColor),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '₦${spendToNext.toStringAsFixed(0)} more to $nextTier',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Tier perks ──────────────────────────────────────────────
            Text('Your $tier perks', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            ..._perks(tier).map(
              (perk) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 18, color: tierColor),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(perk,
                          style: theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── All tiers overview ──────────────────────────────────────
            Text('All Tiers', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            _TierRow(tier: 'Bronze', spend: '₦0+', theme: theme,
                color: AppColors.emerald, current: tier == 'Bronze'),
            _TierRow(tier: 'Silver', spend: '₦5,000+', theme: theme,
                color: const Color(0xFF6B7280), current: tier == 'Silver'),
            _TierRow(tier: 'Gold', spend: '₦20,000+', theme: theme,
                color: const Color(0xFFB45309), current: tier == 'Gold'),
            _TierRow(tier: 'Platinum', spend: '₦50,000+', theme: theme,
                color: const Color(0xFF6D28D9), current: tier == 'Platinum'),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Color _tierColor(String t) => switch (t) {
        'Silver' => const Color(0xFF6B7280),
        'Gold' => const Color(0xFFB45309),
        'Platinum' => const Color(0xFF6D28D9),
        _ => AppColors.emerald,
      };

  IconData _tierIcon(String t) => switch (t) {
        'Silver' => Icons.workspace_premium,
        'Gold' => Icons.military_tech,
        'Platinum' => Icons.diamond,
        _ => Icons.star,
      };

  String? _nextTier(String t) => switch (t) {
        'Bronze' => 'Silver',
        'Silver' => 'Gold',
        'Gold' => 'Platinum',
        _ => null,
      };

  double _tierProgress(double spending) {
    if (spending >= 50000) return 1.0;
    if (spending >= 20000) return (spending - 20000) / 30000;
    if (spending >= 5000) return (spending - 5000) / 15000;
    return spending / 5000;
  }

  double _spendToNext(double spending) {
    if (spending >= 50000) return 0;
    if (spending >= 20000) return 50000 - spending;
    if (spending >= 5000) return 20000 - spending;
    return 5000 - spending;
  }

  List<String> _perks(String tier) => switch (tier) {
        'Silver' => [
            '1.5× reward points per order',
            '₦500 birthday wallet credit',
            'Priority support',
          ],
        'Gold' => [
            '2× reward points per order',
            '₦1,000 birthday wallet credit',
            'Priority support',
            'Exclusive Gold member offers',
          ],
        'Platinum' => [
            '3× reward points per order',
            '₦2,000 birthday wallet credit',
            'Priority support',
            'Exclusive Platinum member offers',
            'Free delivery on orders above ₦2,000',
          ],
        _ => [
            '1× reward point per ₦100 spent',
            'Access to all core features',
          ],
      };
}

class _CardStat extends StatelessWidget {
  const _CardStat(
      {required this.label, required this.value, required this.theme});
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.pureWhite,
              fontWeight: FontWeight.w700,
            )),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.pureWhite.withValues(alpha: 0.7),
            )),
      ],
    );
  }
}

class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.spend,
    required this.theme,
    required this.color,
    required this.current,
  });
  final String tier;
  final String spend;
  final ThemeData theme;
  final Color color;
  final bool current;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(tier,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight:
                    current ? FontWeight.w700 : FontWeight.w400,
              )),
          if (current) ...[
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text('current',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: color)),
            ),
          ],
          const Spacer(),
          Text(spend,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              )),
        ],
      ),
    );
  }
}
