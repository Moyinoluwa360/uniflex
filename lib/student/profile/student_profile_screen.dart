import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../services/student_providers.dart';
import 'badges_screen.dart';
import 'gift_screen.dart';
import 'membership_card_screen.dart';
import 'preferences_screen.dart';
import 'referral_screen.dart';
import 'scheduled_orders_student_screen.dart';

/// Student profile — rebuilt for Phase 6 with membership, rewards, referral,
/// gifting, scheduled orders, and preferences.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profileAsync = ref.watch(currentProfileProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);
    final statsAsync = ref.watch(studentStatsProvider);

    return Scaffold(
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Profile not found.'));
          }

          final initials = _initials(profile.nickname ?? profile.fullName);
          final tier = statsAsync.valueOrNull?['membership_tier'] as String? ??
              profile.membershipTier;
          final tierColor = _tierColor(tier);
          final points =
              statsAsync.valueOrNull?['reward_points'] as int? ??
                  profile.rewardPoints;

          return CustomScrollView(
            slivers: [
              // ── Hero header ──────────────────────────────────────────
              SliverToBoxAdapter(
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenGutter,
                    MediaQuery.of(context).padding.top + AppSpacing.lg,
                    AppSpacing.screenGutter,
                    AppSpacing.xl,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [tierColor, tierColor.withValues(alpha: 0.7)],
                    ),
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.pureWhite.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.pureWhite.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            initials,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: AppColors.pureWhite,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        profile.nickname ?? profile.fullName ?? '—',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: AppColors.pureWhite),
                      ),
                      if (profile.fullName != null && profile.nickname != null)
                        Text(
                          profile.fullName!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.pureWhite.withValues(alpha: 0.8),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      // Tier badge + points
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.pureWhite.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              tier,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.pureWhite,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.pureWhite.withValues(alpha: 0.2),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              '$points pts',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: AppColors.pureWhite,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.screenGutter),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Wallet balance ──────────────────────────────────
                    _SectionCard(
                      children: [
                        _InfoRow(
                          icon: Icons.account_balance_wallet_outlined,
                          label: 'Wallet balance',
                          value: balanceAsync.when(
                            data: (b) => '₦${(b ?? 0).toStringAsFixed(2)}',
                            loading: () => '…',
                            error: (_, __) => '—',
                          ),
                          theme: theme,
                          valueColor: theme.colorScheme.primary,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.cardGap),

                    // ── Services menu ───────────────────────────────────
                    _SectionLabel(label: 'Services', theme: theme),
                    const SizedBox(height: AppSpacing.sm),
                    _SectionCard(
                      children: [
                        _MenuRow(
                          icon: Icons.workspace_premium_outlined,
                          label: 'Membership & Rewards',
                          onTap: () => _push(
                              context, MembershipCardScreen(profile: profile)),
                          theme: theme,
                        ),
                        _MenuRow(
                          icon: Icons.people_outline,
                          label: 'Refer a Friend',
                          onTap: () => _push(
                              context, ReferralScreen(profile: profile)),
                          theme: theme,
                        ),
                        _MenuRow(
                          icon: Icons.card_giftcard_outlined,
                          label: 'Send a Gift',
                          onTap: () =>
                              _push(context, const GiftScreen()),
                          theme: theme,
                        ),
                        _MenuRow(
                          icon: Icons.emoji_events_outlined,
                          label: 'My Badges',
                          onTap: () =>
                              _push(context, const BadgesScreen()),
                          theme: theme,
                        ),
                        _MenuRow(
                          icon: Icons.schedule_outlined,
                          label: 'Scheduled Orders',
                          showDivider: false,
                          onTap: () => _push(
                              context,
                              const ScheduledOrdersStudentScreen()),
                          theme: theme,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.cardGap),

                    // ── Account info ────────────────────────────────────
                    _SectionLabel(label: 'Account', theme: theme),
                    const SizedBox(height: AppSpacing.sm),
                    _SectionCard(
                      children: [
                        if (profile.matricNumber != null)
                          _InfoRow(
                            icon: Icons.badge_outlined,
                            label: 'Matric number',
                            value: profile.matricNumber!,
                            theme: theme,
                          ),
                        if (profile.school != null)
                          _InfoRow(
                            icon: Icons.school_outlined,
                            label: 'School',
                            value: profile.school!,
                            theme: theme,
                          ),
                        if (profile.email != null)
                          _InfoRow(
                            icon: Icons.email_outlined,
                            label: 'Email',
                            value: profile.email!,
                            theme: theme,
                          ),
                        if (profile.phone != null)
                          _InfoRow(
                            icon: Icons.phone_outlined,
                            label: 'Phone',
                            value: profile.phone!,
                            theme: theme,
                          ),
                        if (profile.referralCode != null)
                          _ReferralRow(
                              code: profile.referralCode!, theme: theme),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.cardGap),

                    // ── More menu ───────────────────────────────────────
                    _SectionLabel(label: 'More', theme: theme),
                    const SizedBox(height: AppSpacing.sm),
                    _SectionCard(
                      children: [
                        _MenuRow(
                          icon: Icons.settings_outlined,
                          label: 'Preferences',
                          onTap: () =>
                              _push(context, const PreferencesScreen()),
                          theme: theme,
                        ),
                        _MenuRow(
                          icon: Icons.logout,
                          label: 'Log out',
                          iconColor: AppColors.error,
                          labelColor: AppColors.error,
                          showDivider: false,
                          showChevron: false,
                          onTap: () =>
                              ref.read(authServiceProvider).signOut(),
                          theme: theme,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.xl),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen));
  }

  Color _tierColor(String tier) => switch (tier) {
        'Silver' => const Color(0xFF6B7280),
        'Gold' => const Color(0xFFB45309),
        'Platinum' => const Color(0xFF6D28D9),
        _ => AppColors.emerald,
      };

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

// ── Shared helpers ────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
  });
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color:
                  theme.colorScheme.primary.withValues(alpha: 0.7)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    )),
                Text(value,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: valueColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.theme,
    this.iconColor,
    this.labelColor,
    this.showDivider = true,
    this.showChevron = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeData theme;
  final Color? iconColor;
  final Color? labelColor;
  final bool showDivider;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: iconColor ??
                        theme.colorScheme.onSurface
                            .withValues(alpha: 0.6)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: labelColor)),
                ),
                if (showChevron)
                  Icon(Icons.chevron_right,
                      size: 18,
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.3)),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }
}

class _ReferralRow extends StatelessWidget {
  const _ReferralRow({required this.code, required this.theme});
  final String code;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.card_giftcard_outlined, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your referral code',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5))),
              Text(code, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy_outlined, size: 18),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Referral code copied')),
            );
          },
        ),
      ],
    );
  }
}
