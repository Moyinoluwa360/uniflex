import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/profile.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/widgets/tier/tier_header.dart';
import '../services/student_providers.dart';

/// Membership card — shows current tier, progress to next, perks list,
/// reward points balance, and order stats.
class MembershipCardScreen extends ConsumerWidget {
  const MembershipCardScreen({super.key, required this.profile});

  final Profile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final statsAsync = ref.watch(studentStatsProvider);

    final tier = statsAsync.valueOrNull?['membership_tier'] as String? ??
        profile.membershipTier;
    final points = statsAsync.valueOrNull?['reward_points'] as int? ??
        profile.rewardPoints;
    final spending =
        (statsAsync.valueOrNull?['lifetime_spending'] as num?)?.toDouble() ??
            profile.lifetimeSpending;
    final totalOrders =
        statsAsync.valueOrNull?['total_orders'] as int? ?? profile.totalOrders;

    final progress = _tierProgress(spending);
    final nextTier = _nextTier(tier);
    final spendToNext = _spendToNext(spending);
    final name = profile.nickname ?? profile.fullName ?? '—';

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Membership'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Membership card ─────────────────────────────────────────
            TierHeader(
              tier: tier,
              name: name,
              initial: name.isEmpty ? '?' : name,
            ),
            const SizedBox(height: AppSpacing.cardGap),
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _CardStat(label: 'Reward Points', value: '$points'),
                  _CardStat(label: 'Orders', value: '$totalOrders'),
                  _CardStat(label: 'Spent', value: Money.format(spending)),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── Progress to next tier ───────────────────────────────────
            if (nextTier != null) ...[
              AppSectionLabel('Progress to $nextTier'),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: c.surfaceRaised,
                  valueColor: AlwaysStoppedAnimation<Color>(c.brand),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${Money.format(spendToNext)} more to $nextTier',
                style: AppTypography.caption(c),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Tier perks ──────────────────────────────────────────────
            AppSectionLabel('Your $tier perks'),
            const SizedBox(height: AppSpacing.sm),
            ..._perks(tier).map(
              (perk) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  children: [
                    Icon(AppIcons.check, size: 18, color: c.brandText),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(perk, style: AppTypography.body(c)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.lg),

            // ── All tiers overview ──────────────────────────────────────
            const AppSectionLabel('All Tiers'),
            const SizedBox(height: AppSpacing.sm),
            AppListGroup(
              children: [
                _tierRow('Bronze', '₦0+', tier),
                _tierRow('Silver', '₦5,000+', tier),
                _tierRow('Gold', '₦20,000+', tier),
                _tierRow('Platinum', '₦50,000+', tier),
              ],
            ),

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _tierRow(String name, String spend, String current) => AppListRow(
        title: name,
        subtitle: current == name ? 'current' : null,
        showChevron: false,
        trailing: Builder(
          builder: (context) => Text(
            spend,
            style: AppTypography.tabular(AppTypography.meta(context.colors)),
          ),
        ),
      );

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
  const _CardStat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        Text(value, style: AppTypography.tabular(AppTypography.title(c))),
        Text(label, style: AppTypography.caption(c)),
      ],
    );
  }
}
