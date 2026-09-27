import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/models/around_category.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/media/app_image.dart';
import '../../shared/widgets/navigation/app_bottom_nav_shell.dart';
import '../around/around_category_providers.dart';
import '../around/around_screen.dart';
import '../notifications/notifications_screen.dart';
import '../ordering/cart_provider.dart';
import '../ordering/cart_screen.dart';
import '../ordering/catalog_screen.dart';
import '../ordering/product_repository.dart';
import '../services/student_providers.dart';

/// Index of the Wallet tab in [StudentShell] — used by the header's
/// "Top up" affordance to jump straight to it.
const int _kWalletTabIndex = 2;

/// Index of the Profile tab in [StudentShell] — used by the header's
/// avatar to jump straight to it.
const int _kProfileTabIndex = 3;

/// Soft emerald glow beneath vendor cards — a tight, low-opacity brand
/// shadow that lifts the cards off the canvas (per the design).
final List<BoxShadow> _cardGlow = [
  BoxShadow(
    color: AppColors.emerald.withValues(alpha: 0.16),
    blurRadius: 18,
    spreadRadius: -6,
    offset: const Offset(0, 10),
  ),
];

enum _HomeMode { around, foodDelivery }

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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _HomeHeader(
              greeting: _greeting(),
              nickname: nickname,
              balance: balance,
              searchHint: isFood
                  ? 'Search meals, vendors, errands'
                  : 'Search errands, hostels, vendors',
              onTopUp: () => AppNavShellScope.of(context)?.go(_kWalletTabIndex),
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
            const SliverToBoxAdapter(
              child: _SectionHeader(
                title: 'Vendors around you',
                action: 'See all',
              ),
            ),
            const SliverToBoxAdapter(child: _VendorList()),
          ] else ...[
            const SliverToBoxAdapter(child: _AroundServiceGrid()),
            const SliverToBoxAdapter(child: _RunnersOnline()),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ],
      ),
      // Post-testing fixes, Section 13: a persistent, badge-carrying cart
      // button visible from Home whenever the cart is non-empty — there
      // used to be no way to reach the cart from Home at all.
      floatingActionButton: const _HomeCartButton(),
    );
  }
}

class _HomeCartButton extends ConsumerWidget {
  const _HomeCartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    if (cart.isEmpty || cart.vendor == null) return const SizedBox.shrink();

    return Badge(
      label: Text('${cart.itemCount}'),
      backgroundColor: AppColors.orange,
      child: FloatingActionButton(
        heroTag: 'home_cart_fab',
        backgroundColor: AppColors.orange,
        foregroundColor: AppColors.pureWhite,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CartScreen(vendor: cart.vendor!),
          ),
        ),
        child: const Icon(Icons.shopping_cart_outlined),
      ),
    );
  }
}

/// The header's bell, badged with the unread count and opening the inbox.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    final bell = _GlassCircle(
      child: const Icon(Icons.notifications_none_rounded,
          color: AppColors.pureWhite, size: 22),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      ),
    );

    if (unread == 0) return bell;

    return Badge(
      label: Text('${unread > 9 ? '9+' : unread}'),
      backgroundColor: AppColors.orange,
      textColor: AppColors.pureWhite,
      child: bell,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const white = AppColors.pureWhite;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [AppColors.darkEmerald, AppColors.darkCanvas]
              : const [AppColors.emerald, AppColors.splashGradientMid],
        ),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(AppRadius.sheet),
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
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: white.withValues(alpha: 0.85)),
                    ),
                    Text(
                      nickname,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: white, height: 1.1),
                    ),
                  ],
                ),
              ),
              const _NotificationBell(),
              const SizedBox(width: AppSpacing.sm),
              // Avatar — emerald in dark mode, white in light. Tapping
              // routes to the Profile tab.
              Material(
                color: isDark ? AppColors.emerald : white,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onAvatarTap,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: Text(
                        nickname.trim().isNotEmpty
                            ? nickname.trim()[0].toUpperCase()
                            : 'U',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color:
                              isDark ? AppColors.pureWhite : AppColors.emerald,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Wallet balance card (glass)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md - 2,
            ),
            decoration: BoxDecoration(
              color: white.withValues(alpha: isDark ? 0.08 : 0.16),
              borderRadius: BorderRadius.circular(AppRadius.control),
              border: Border.all(color: white.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'WALLET BALANCE',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: white.withValues(alpha: 0.75),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        balance != null
                            ? '₦${balance!.toStringAsFixed(2)}'
                            : '₦--',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _TopUpButton(onTap: onTopUp),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // Search bar — dark surface in dark mode, white in light
          GestureDetector(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Search coming soon')),
            ),
            child: Container(
              height: AppSpacing.controlHeight - 8,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : white,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: isDark
                    ? Border.all(color: AppColors.darkHairline)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Icon(Icons.search,
                      color: isDark
                          ? AppColors.darkInkSecondary
                          : AppColors.mediumGrey,
                      size: 20),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      searchHint,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDark
                            ? AppColors.darkInkSecondary
                            : AppColors.mediumGrey,
                      ),
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

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.pureWhite.withValues(alpha: 0.16),
          shape: BoxShape.circle,
          border: Border.all(
              color: AppColors.pureWhite.withValues(alpha: 0.18)),
        ),
        child: child,
      ),
    );
  }
}

class _TopUpButton extends StatelessWidget {
  const _TopUpButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Emerald fill in dark mode (pops against the deep-green header),
    // white in light mode. Dark ink reads on both.
    final bg = isDark ? AppColors.emerald : AppColors.pureWhite;
    const fg = AppColors.matteBlack;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 16, color: fg),
            const SizedBox(width: 4),
            Text(
              'Top up',
              style: theme.textTheme.labelMedium?.copyWith(
                color: fg,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});
  final String title;
  final String? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(
              action!,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary),
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        0,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            _ToggleTab(
              label: 'Around',
              icon: Icons.explore_outlined,
              selected: mode == _HomeMode.around,
              onTap: () => onChanged(_HomeMode.around),
            ),
            _ToggleTab(
              label: 'Food Delivery',
              icon: Icons.restaurant_outlined,
              selected: mode == _HomeMode.foodDelivery,
              onTap: () => onChanged(_HomeMode.foodDelivery),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  const _ToggleTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? theme.colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.control - 4),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected && label == 'Around'
                    ? Icons.check_circle
                    : icon,
                size: 16,
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Promo banner carousel ────────────────────────────────────────────────────

class _PromoBannerCarousel extends ConsumerStatefulWidget {
  const _PromoBannerCarousel();

  @override
  ConsumerState<_PromoBannerCarousel> createState() =>
      _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends ConsumerState<_PromoBannerCarousel> {
  final _controller = PageController(viewportFraction: 0.86);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Acts on an ad's configured tap target. Unknown or malformed targets do
  /// nothing rather than throwing — an ad is content, so a bad link should
  /// never break the home screen.
  Future<void> _openAd(Advertisement ad) async {
    switch (ad.linkType) {
      case AdLinkType.none:
        return;
      case AdLinkType.wallet:
        ref.read(shellTabRequestProvider.notifier).state = _kWalletTabIndex;
      case AdLinkType.vendor:
        final vendorId = ad.linkValue;
        if (vendorId == null) return;
        final vendors = await ref.read(vendorsProvider.future);
        final vendor = vendors.where((v) => v.id == vendorId).firstOrNull;
        if (vendor == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => CatalogScreen(vendor: vendor)),
        );
      case AdLinkType.url:
        final raw = ad.linkValue;
        if (raw == null) return;
        final uri = Uri.tryParse(raw);
        if (uri == null || !uri.hasScheme) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final adsAsync = ref.watch(liveAdvertisementsProvider);
    final ads = adsAsync.valueOrNull ?? const <Advertisement>[];

    // No ads scheduled is a normal state, not an error — take up no space.
    if (ads.isEmpty) return const SizedBox.shrink();

    // Guard against the page index dangling past the end when an ad expires
    // or admin removes one while the screen is open.
    final page = _page.clamp(0, ads.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 128,
          child: PageView.builder(
            controller: _controller,
            // Align the strip flush to the left gutter rather than
            // centring each page in the viewport.
            padEnds: false,
            itemCount: ads.length,
            onPageChanged: (p) => setState(() => _page = p),
            itemBuilder: (context, i) {
              final ad = ads[i];
              return Padding(
                padding: EdgeInsets.only(
                  left: i == 0 ? AppSpacing.screenGutter : AppSpacing.sm,
                  right: i == ads.length - 1
                      ? AppSpacing.screenGutter
                      : AppSpacing.sm,
                ),
                child: _PromoCard(
                  title: ad.title,
                  subtitle: ad.subtitle,
                  dark: ad.isDark,
                  imageUrl: ad.imageUrl,
                  onTap: ad.linkType == AdLinkType.none
                      ? null
                      : () => _openAd(ad),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Dots — left-aligned under the strip, tracking the gutter.
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.screenGutter),
          child: Row(
            children: List.generate(
              ads.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: page == i ? 16 : 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: page == i
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A promo strip card. Beyond the flat colour it carries a pair of very
/// faint concentric circles bleeding off the right edge — the subtle
/// interior shape the design uses so the cards don't read as plain boxes.
class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.title,
    required this.subtitle,
    required this.dark,
    this.imageUrl,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final bool dark;

  /// Optional artwork behind the text. When set it replaces the decorative
  /// circles and gets a scrim so the copy stays readable over any photo.
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = dark ? AppColors.matteBlack : AppColors.orange;
    final shape = AppColors.pureWhite.withValues(alpha: dark ? 0.05 : 0.09);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Material(
        color: base,
        child: InkWell(
          onTap: onTap,
          child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage) ...[
              AppImage(url: imageUrl, fit: BoxFit.cover),
              // Left-weighted scrim: keeps the title legible without
              // flattening the whole photo.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      AppColors.matteBlack.withValues(alpha: 0.72),
                      AppColors.matteBlack.withValues(alpha: 0.15),
                    ],
                  ),
                ),
              ),
            ] else ...[
              // Subtle interior shapes — soft concentric circles off the right.
              Positioned(
                right: -34,
                top: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: shape),
                ),
              ),
              Positioned(
                right: 26,
                bottom: -52,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: shape),
                ),
              ),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.pureWhite),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.pureWhite.withValues(alpha: 0.85),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
      ),
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
                        child:
                            _PartnerVendorCard(vendor: e.value, seed: e.key + 10),
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
    final theme = Theme.of(context);
    final color = onDark
        ? AppColors.pureWhite.withValues(alpha: 0.85)
        : theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Row(
      children: [
        Icon(Icons.star_rounded,
            size: 15, color: onDark ? AppColors.pureWhite : AppColors.orange),
        const SizedBox(width: 3),
        Text('4.9  ·  15–20 min  ·  ₦300',
            style: theme.textTheme.labelSmall?.copyWith(color: color)),
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
          boxShadow: _cardGlow,
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
                  top: AppSpacing.sm,
                  left: AppSpacing.sm,
                  child: _Badge(
                    label: (vendor.badgeLabel ?? 'Major').toUpperCase(),
                    background: AppColors.orange,
                    foreground: AppColors.pureWhite,
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
                            const Icon(Icons.verified,
                                size: 16, color: AppColors.emerald),
                            const SizedBox(width: AppSpacing.sm),
                            _Badge(
                              label: 'OPEN',
                              background:
                                  AppColors.emerald.withValues(alpha: 0.15),
                              foreground: AppColors.emerald,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vendor.description.isNotEmpty
                              ? vendor.description
                              : 'Rice bowls · Grills · Small chops',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const _VendorMetaRow(onDark: false),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.pureWhite,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => CatalogScreen(vendor: vendor)),
                    ),
                    child: const Text('Order'),
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
          boxShadow: _cardGlow,
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _VendorMetaRow(onDark: false),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
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

// ── Around service grid ──────────────────────────────────────────────────────

/// Reads categories from the admin-configurable `around_categories` table
/// (post-testing fixes, Section 9) instead of a hardcoded enum, so
/// add/edit/remove from the admin Manage hub shows up here immediately.
class _AroundServiceGrid extends ConsumerWidget {
  const _AroundServiceGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(activeAroundCategoriesProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        0,
      ),
      child: categoriesAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => RetrySection(
          message: 'Could not load Around categories.',
          onRetry: () => ref.invalidate(activeAroundCategoriesProvider),
          compact: true,
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return Text(
              'No Around services available right now.',
              style: theme.textTheme.bodyMedium,
            );
          }
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: AppSpacing.cardGap,
            mainAxisSpacing: AppSpacing.cardGap,
            childAspectRatio: 1.5,
            children: [
              for (final category in categories)
                _AroundServiceCard(category: category),
            ],
          );
        },
      ),
    );
  }
}

class _AroundServiceCard extends StatelessWidget {
  const _AroundServiceCard({required this.category});
  final AroundCategoryData category;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => AroundScreen(category: category)),
      ),
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: theme.dividerColor),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.control - 4),
              ),
              child: Icon(category.icon,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const Spacer(),
            Text(category.title,
                style: theme.textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              category.subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rider availability ───────────────────────────────────────────────────────

/// Anonymous availability indicator for Around requests. Deliberately shows
/// no individual rider's name or an "online" status tied to a person — just
/// a dot signalling whether riders are available nearby right now.
class _RunnersOnline extends ConsumerWidget {
  const _RunnersOnline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ridersAvailableAsync = ref.watch(ridersAvailableNearbyProvider);
    final ridersAvailable = ridersAvailableAsync.valueOrNull ?? false;
    final categories = ref.watch(activeAroundCategoriesProvider).valueOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rider availability', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Container(
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: theme.dividerColor),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: ridersAvailable
                        ? AppColors.emerald
                        : theme.colorScheme.onSurface.withValues(alpha: 0.25),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    ridersAvailable
                        ? 'Riders available nearby'
                        : 'No riders available right now',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.emerald,
                    foregroundColor: AppColors.pureWhite,
                    minimumSize: const Size(0, 40),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  ),
                  onPressed: (categories == null || categories.isEmpty)
                      ? null
                      : () {
                          final errand = categories.firstWhere(
                            (c) => c.key == 'errand',
                            orElse: () => categories.first,
                          );
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AroundScreen(category: errand),
                            ),
                          );
                        },
                  child: const Text('Request'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
