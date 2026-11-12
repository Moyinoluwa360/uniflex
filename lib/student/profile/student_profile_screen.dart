import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/support/support_chat_service.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/widgets/tier/tier_header.dart';
import '../services/student_providers.dart';
import '../support/support_options_screen.dart';
import 'badges_screen.dart';
import '../gifts/gifts_screen.dart';
import 'membership_card_screen.dart';
import 'preferences_screen.dart';
import 'refer_a_student_screen.dart';
import 'scheduled_orders_student_screen.dart';

/// Student profile — rebuilt for Phase 6 with membership, rewards, referral,
/// gifting, scheduled orders, and preferences.
class StudentProfileScreen extends ConsumerWidget {
  const StudentProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
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

          return CustomScrollView(
            slivers: [
              // ── Header ────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.lg,
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                    ),
                    child: TierHeader(
                      tier: tier,
                      name: profile.fullName ?? profile.nickname ?? '—',
                      nickname:
                          profile.fullName != null ? profile.nickname : null,
                      initial: initials,
                    ),
                  ),
                ),
              ),

              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.screenGutter,
                  AppSpacing.screenGutter,
                  AppSpacing.navClearanceOf(context) + AppSpacing.md,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // ── Wallet balance ──────────────────────────────────
                    AppListGroup(
                      children: [
                        AppListRow(
                          leadingIcon: AppIcons.wallet,
                          title: balanceAsync.when(
                            data: (b) => Money.hero(b ?? 0),
                            loading: () => '…',
                            error: (_, __) => '—',
                          ),
                          subtitle: 'Wallet balance',
                          showChevron: false,
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── Services menu ───────────────────────────────────
                    const AppSectionLabel('Services'),
                    const SizedBox(height: AppSpacing.sm),
                    AppListGroup(
                      children: [
                        AppListRow(
                          leadingIcon: AppIcons.award,
                          title: 'Membership & Rewards',
                          onTap: () => _push(
                              context, MembershipCardScreen(profile: profile)),
                        ),
                        AppListRow(
                          leadingIcon: AppIcons.group,
                          title: 'Refer a student',
                          onTap: () =>
                              _push(context, const ReferAStudentScreen()),
                        ),
                        AppListRow(
                          leadingIcon: AppIcons.gift,
                          title: 'Gifts',
                          onTap: () => _push(context, const GiftsScreen()),
                        ),
                        AppListRow(
                          leadingIcon: AppIcons.trophy,
                          title: 'My Badges',
                          onTap: () => _push(context, const BadgesScreen()),
                        ),
                        AppListRow(
                          leadingIcon: AppIcons.clock,
                          title: 'Scheduled Orders',
                          onTap: () => _push(
                              context, const ScheduledOrdersStudentScreen()),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── Account info ────────────────────────────────────
                    const AppSectionLabel('Account'),
                    const SizedBox(height: AppSpacing.sm),
                    AppListGroup(
                      children: [
                        if (profile.matricNumber != null)
                          AppListRow(
                            leadingIcon: AppIcons.receipt,
                            title: profile.matricNumber!,
                            subtitle: 'Matric number',
                            showChevron: false,
                          ),
                        if (profile.school != null)
                          AppListRow(
                            leadingIcon: AppIcons.award,
                            title: profile.school!,
                            subtitle: 'School',
                            showChevron: false,
                          ),
                        if (profile.email != null)
                          AppListRow(
                            leadingIcon: AppIcons.mail,
                            title: profile.email!,
                            subtitle: 'Email',
                            showChevron: false,
                          ),
                        if (profile.phone != null)
                          AppListRow(
                            leadingIcon: AppIcons.phone,
                            title: profile.phone!,
                            subtitle: 'Phone',
                            showChevron: false,
                          ),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.md),

                    // ── More menu ───────────────────────────────────────
                    const AppSectionLabel('More'),
                    const SizedBox(height: AppSpacing.sm),
                    AppListGroup(
                      children: [
                        // Help & Support — badge shows when admin replies.
                        Consumer(
                          builder: (context, ref, _) {
                            final unread = ref
                                    .watch(myConversationProvider)
                                    .valueOrNull
                                    ?.studentUnreadCount ??
                                0;
                            return AppListRow(
                              leadingIcon: AppIcons.chat,
                              title: 'Help & Support',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (unread > 0) ...[
                                    Badge(
                                      label: Text('$unread'),
                                      backgroundColor: c.brand,
                                      textColor: c.onBrand,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                  ],
                                  Icon(AppIcons.chevronRight,
                                      size: AppIconSize.small,
                                      color: c.textTertiary),
                                ],
                              ),
                              onTap: () =>
                                  _push(context, const SupportOptionsScreen()),
                            );
                          },
                        ),
                        AppListRow(
                          leadingIcon: AppIcons.manage,
                          title: 'Preferences',
                          onTap: () =>
                              _push(context, const PreferencesScreen()),
                        ),
                        const _ChangePinRow(),
                      ],
                    ),

                    const SizedBox(height: AppSpacing.lg),

                    AppButton(
                      label: 'Log out',
                      icon: AppIcons.logout,
                      variant: AppButtonVariant.quietDanger,
                      onPressed: () async {
                        final ok = await AppDialog.show(
                          context,
                          title: 'Log out?',
                          body:
                              'You will need to sign in again to use Uniflex.',
                          secondaryLabel: 'Stay signed in',
                          confirmLabel: 'Log out',
                          destructive: true,
                        );
                        if (ok == true) {
                          ref.read(authServiceProvider).signOut();
                        }
                      },
                    ),
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }
}

/// "Change Transaction PIN" row (Pack 1 / 1.4).
///
/// Cause of the "slow / ignores taps" report: `showSetPinSheet` first awaits a
/// network call (`hasTransactionPin`) before the sheet appears, and the row
/// gave no feedback meanwhile — so on a slow connection the first tap looked
/// ignored and further taps queued extra checks and sheets. This row shows a
/// spinner at once and ignores repeat taps until the sheet has closed
/// (saved, error, dismissed or back). What the PIN flow does, validates and
/// stores is unchanged: it is the same `showSetPinSheet` call.
class _ChangePinRow extends ConsumerStatefulWidget {
  const _ChangePinRow();

  @override
  ConsumerState<_ChangePinRow> createState() => _ChangePinRowState();
}

class _ChangePinRowState extends ConsumerState<_ChangePinRow> {
  bool _busy = false;

  Future<void> _open() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showSetPinSheet(context, ref);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppListRow(
      key: const ValueKey('change-pin-row'),
      leadingIcon: AppIcons.lock,
      title: 'Change Transaction PIN',
      trailing: _busy
          ? SizedBox(
              width: AppIconSize.small,
              height: AppIconSize.small,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.textTertiary,
              ),
            )
          : null,
      onTap: _open,
    );
  }
}
