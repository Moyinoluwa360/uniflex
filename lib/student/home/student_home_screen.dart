import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/models/order.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/buttons/promo_cart_button.dart';
import '../../shared/widgets/chips/dark_glass_chip.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/home/home_header_parts.dart';
import '../../shared/widgets/media/app_image.dart';
import '../../shared/widgets/navigation/app_bottom_nav_shell.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/tabs/app_segmented_tabs.dart';
import '../errand/create_errand_screen.dart';
import '../notifications/notifications_screen.dart';
import '../ordering/cart_provider.dart';
import '../ordering/cart_screen.dart';
import '../ordering/catalog_screen.dart';
import '../ordering/order_repository.dart';
import '../ordering/product_repository.dart';
import '../services/student_providers.dart';
import '../tracking/errand_tracking_screen.dart';
import 'ad_popup.dart';
import 'ad_carousel.dart';
import 'all_vendors_screen.dart';
import 'search_screen.dart';

/// Index of the Wallet tab in [StudentShell] — used by the header's
/// "Top up" affordance to jump straight to it.
const int _kWalletTabIndex = 2;

/// Index of the Profile tab in [StudentShell] — used by the header's
/// avatar to jump straight to it.
const int _kProfileTabIndex = 3;

/// Soft brand glow beneath vendor cards (kept from the original Home).
List<BoxShadow> _cardGlow(BuildContext context) => [
      BoxShadow(
        color: context.colors.brand.withValues(alpha: 0.16),
        blurRadius: 18,
        spreadRadius: -6,
        offset: const Offset(0, 10),
      ),
    ];

enum _HomeMode { foodDelivery, errand }

class StudentHomeScreen extends ConsumerStatefulWidget {
  const StudentHomeScreen({super.key});

  @override
  ConsumerState<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends ConsumerState<StudentHomeScreen> {
  _HomeMode _mode = _HomeMode.foodDelivery;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);

    final nickname = profileAsync.whenOrNull(
          data: (profile) => profile?.nickname ?? 'there',
        ) ??
        'there';
    final balance = balanceAsync.whenOrNull(data: (b) => b);
    final isFood = _mode == _HomeMode.foodDelivery;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _HomeHeader(
                  greeting: _greeting(),
                  nickname: nickname,
                  balance: balance,
                  searchHint: isFood
                      ? 'Search meals, vendors, errands'
                      : 'Search errands, hostels, vendors',
                  onTopUp: () =>
                      AppNavShellScope.of(context)?.go(_kWalletTabIndex),
                  onAvatarTap: () =>
                      AppNavShellScope.of(context)?.go(_kProfileTabIndex),
                ),
              ),
              SliverToBoxAdapter(
                child: _ModeToggle(
                  mode: _mode,
                  onChanged: (m) => setState(() => _mode = m),
                ),
              ),
              if (isFood) ...[
                const SliverToBoxAdapter(child: _PromoBannerCarousel()),
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: 'Vendors around you',
                    action: 'See all',
                    onAction: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const AllVendorsScreen()),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: _VendorList()),
              ] else ...[
                const SliverToBoxAdapter(child: _ErrandSection()),
              ],
              // Room for the floating glass nav bar (and the cart button).
              SliverToBoxAdapter(
                child: SizedBox(
                  height: AppSpacing.navClearanceOf(context) + AppSpacing.xl,
                ),
              ),
            ],
          ),
          // Post-testing fixes, Section 13: a persistent, badge-carrying cart
          // button visible from Home whenever the cart is non-empty. Lifted
          // so it clears the glass nav bar.
          Positioned(
            right: AppSpacing.md,
            bottom: AppSpacing.navClearanceOf(context) + 12,
            child: const _HomeCartButton(),
          ),
        ],
      ),
    );
  }
}

class _HomeCartButton extends ConsumerWidget {
  const _HomeCartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty || cart.vendor == null) return const SizedBox.shrink();

    return PromoCartButton(
      count: cart.itemCount,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const CartScreen(),
        ),
      ),
    );
  }
}

/// The header's bell: shows a dot when something is unread, opens the inbox.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return HeaderGlassButton(
      icon: AppIcons.bell,
      semanticLabel: 'Notifications',
      showDot: unread > 0,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.greeting,
    required this.nickname,
    required this.balance,
    required this.searchHint,
    required this.onTopUp,
    required this.onAvatarTap,
  });

  final String greeting;
  final String nickname;
  final double? balance;
  final String searchHint;
  final VoidCallback onTopUp;
  final VoidCallback onAvatarTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      decoration: BoxDecoration(
        gradient: c.homeHeaderGradient,
        border: Border(bottom: BorderSide(color: c.headerBorder)),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.header),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Greeting + notification bell + avatar
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      greeting,
                      style: AppTypography.body(c)
                          .copyWith(color: c.headerTextSecondary),
                    ),
                    Text(
                      nickname,
                      style: AppTypography.greetingName(c.headerText)
                          .copyWith(height: 1.1),
                    ),
                  ],
                ),
              ),
              const _NotificationBell(),
              const SizedBox(width: AppSpacing.sm),
              // Tapping the avatar routes to the Profile tab.
              HeaderAvatar(
                initial: nickname.trim().isNotEmpty
                    ? nickname.trim()[0].toUpperCase()
                    : 'U',
                onTap: onAvatarTap,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Wallet balance + Top up (glass panel)
          HeaderWalletPanel(
            label: 'WALLET BALANCE',
            balance: balance,
            onTopUp: onTopUp,
          ),
          const SizedBox(height: AppSpacing.md),
          // Search bar
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            child: Container(
              height: AppSpacing.controlHeight - 8,
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.input),
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(AppIcons.search, color: c.headerSearchInk, size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      searchHint,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.body(c)
                          .copyWith(color: c.headerSearchInk),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: c.brandText),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Mode toggle ──────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _HomeMode mode;
  final ValueChanged<_HomeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        0,
      ),
      child: AppSegmentedTabs(
        labels: const ['Food Delivery', 'Errand'],
        index: mode.index,
        onChanged: (i) => onChanged(_HomeMode.values[i]),
      ),
    );
  }
}

// ── Promo banner carousel ────────────────────────────────────────────────────

/// Home banner strip: live ads in an [AdCarousel]. Tapping any ad opens the
/// ad popup (the whole image, plus a Visit button when it has a link).
class _PromoBannerCarousel extends ConsumerWidget {
  const _PromoBannerCarousel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(liveAdvertisementsProvider).valueOrNull ??
        const <Advertisement>[];
    // No ads scheduled is a normal state, not an error — take up no space.
    if (ads.isEmpty) return const SizedBox.shrink();
    return AdCarousel(
      ads: ads,
      onTap: (ad) => showAdPopup(context, ad),
    );
  }
}

// ── Vendor list ──────────────────────────────────────────────────────────────

class _VendorList extends ConsumerWidget {
  const _VendorList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(vendorsProvider);
    final theme = Theme.of(context);

    return vendorsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => RetrySection(
        message: 'Could not load vendors.',
        onRetry: () => ref.invalidate(vendorsProvider),
        compact: true,
      ),
      data: (vendors) {
        if (vendors.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Text(
              'No vendors available right now.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        final uniflex = vendors.firstWhere(
          (v) => v.isUniflex,
          orElse: () => vendors.first,
        );
        final partners = vendors.where((v) => !v.isUniflex).toList();

        return Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
          child: Column(
            children: [
              _UniflexVendorCard(vendor: uniflex),
              if (partners.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.cardGap),
                ...partners.asMap().entries.map(
                      (e) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.cardGap),
                        child: _PartnerVendorCard(
                            vendor: e.value, seed: e.key + 10),
                      ),
                    ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Small rating · time · fee strip shown on vendor cards. The Vendor model
/// carries no rating/prep/fee yet, so these mirror the design's sample
/// values until the data model gains them.
class _VendorMetaRow extends StatelessWidget {
  const _VendorMetaRow({required this.onDark});
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = onDark ? c.headerTextSecondary : c.textSecondary;
    return Row(
      children: [
        Icon(Icons.star_rounded,
            size: 15, color: onDark ? c.headerText : c.statusAmber),
        const SizedBox(width: 3),
        Text('4.9  ·  15–20 min  ·  ${Money.format(300)}',
            style: AppTypography.tabular(
                Theme.of(context).textTheme.labelSmall!.copyWith(color: color))),
      ],
    );
  }
}

class _UniflexVendorCard extends StatelessWidget {
  const _UniflexVendorCard({required this.vendor});
  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CatalogScreen(vendor: vendor)),
      ),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: theme.dividerColor),
          boxShadow: _cardGlow(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero image with badges overlaid
            Stack(
              children: [
                SizedBox(
                  height: 132,
                  width: double.infinity,
                  child: AppImage(
                    url: vendor.imageUrl,
                    keywords: 'jollof,rice,nigerian,food',
                    seed: 1,
                    borderRadius: BorderRadius.zero,
                  ),
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: DarkGlassChip(
                    (vendor.badgeLabel ?? 'Major').toUpperCase(),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                vendor.name,
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.verified,
                                size: 16, color: theme.colorScheme.primary),
                            const SizedBox(width: AppSpacing.sm),
                            _Badge(
                              label: 'OPEN',
                              background: context.colors.brand
                                  .withValues(alpha: 0.15),
                              foreground: context.colors.brandText,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vendor.description.isNotEmpty
                              ? vendor.description
                              : 'Rice bowls · Grills · Small chops',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const _VendorMetaRow(onDark: false),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  AppButton(
                    label: 'Order',
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => CatalogScreen(vendor: vendor)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerVendorCard extends StatelessWidget {
  const _PartnerVendorCard({required this.vendor, required this.seed});
  final Vendor vendor;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CatalogScreen(vendor: vendor)),
      ),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: theme.dividerColor),
          boxShadow: _cardGlow(context),
        ),
        padding: const EdgeInsets.all(AppSpacing.sm + 2),
        child: Row(
          children: [
            SizedBox(
              width: 56,
              height: 56,
              child: AppImage(
                url: vendor.imageUrl,
                keywords: 'restaurant,food',
                seed: seed,
                borderRadius: BorderRadius.circular(AppRadius.control),
                icon: Icons.storefront_outlined,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(vendor.name, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    vendor.description.isNotEmpty
                        ? vendor.description
                        : 'Swallow · Soups · Local',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _VendorMetaRow(onDark: false),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight,
                size: AppIconSize.small, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.background,
    required this.foreground,
  });
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
      ),
    );
  }
}

// ── Errand section ───────────────────────────────────────────────────────────

/// Shows State A (no active errands) or State B (active errand cards).
/// Active = type errand + status not terminal.
class _ErrandSection extends ConsumerWidget {
  const _ErrandSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(studentOrdersProvider);
    final activeErrands = (ordersAsync.valueOrNull ?? const <Order>[])
        .where((o) => o.isErrand && !o.status.isTerminal)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (activeErrands.isEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Column(
                children: [
                  Icon(Icons.explore_outlined,
                      size: 40, color: context.colors.textSecondary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No active errands',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Need something done? Send a rider.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ),
            ),
          ] else ...[
            Text('Active errands', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final order in activeErrands) ...[
              _ErrandOrderCard(order: order),
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
          AppButton(
            icon: AppIcons.add,
            label: 'Create errand',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const CreateErrandScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrandOrderCard extends ConsumerStatefulWidget {
  const _ErrandOrderCard({required this.order});
  final Order order;

  @override
  ConsumerState<_ErrandOrderCard> createState() => _ErrandOrderCardState();
}

class _ErrandOrderCardState extends ConsumerState<_ErrandOrderCard> {
  bool _isCancelling = false;

  Future<void> _cancel() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Cancel errand?',
      body: 'Are you sure you want to cancel this errand?',
      secondaryLabel: 'Keep errand',
      confirmLabel: 'Cancel errand',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await cancelOrder(ref, widget.order.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapCancelError(e.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final status = StatusPresenter.order(order.status, isErrand: true);
    final canCancel = order.riderId == null;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ErrandTrackingScreen(order: order),
        ),
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
            Icon(Icons.explore_outlined,
                size: AppIconSize.regular, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    order.shortId,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppStatusLabel(tone: status.tone, text: status.label),
                ],
              ),
            ),
            if (canCancel)
              _isCancelling
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : IconButton(
                      icon: const Icon(Icons.cancel_outlined),
                      color: context.colors.dangerText,
                      tooltip: 'Cancel errand',
                      onPressed: _cancel,
                    )
            else
              Icon(AppIcons.chevronRight,
                  size: AppIconSize.small, color: context.colors.textTertiary),
          ],
        ),
      ),
    );
  }
}
