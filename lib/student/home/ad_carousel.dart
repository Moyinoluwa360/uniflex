import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/media/app_image.dart';

/// The home-page ad strip.
///
///  * Moves by itself: every [interval] (5 s) it slides to the next ad over
///    [slideDuration] (0.8 s, eased), and after the last ad it loops back to
///    the first.
///  * Stops while a finger is on it, and starts counting again when the
///    finger lifts.
///  * Dots under the strip show where you are.
///  * A single ad is shown still — no paging, no dots, no timer.
///  * Same banner height as before (128) — admin's recommended image ratio
///    is unchanged.
class AdCarousel extends StatefulWidget {
  const AdCarousel({
    super.key,
    required this.ads,
    required this.onTap,
    this.interval = const Duration(seconds: 5),
    this.slideDuration = const Duration(milliseconds: 800),
  });

  final List<Advertisement> ads;
  final void Function(Advertisement ad) onTap;
  final Duration interval;
  final Duration slideDuration;

  @override
  State<AdCarousel> createState() => _AdCarouselState();
}

class _AdCarouselState extends State<AdCarousel> {
  // Start far from 0 so swiping backwards from the first ad also loops.
  static const _startPage = 10000;

  late final PageController _controller;
  Timer? _timer;
  int _page = 0; // index into ads, always 0..n-1

  int get _count => widget.ads.length;
  bool get _moves => _count > 1;

  @override
  void initState() {
    super.initState();
    // Start on a multiple of the ad count so page % count == 0, i.e. the
    // FIRST ad is the one showing (and the first dot the one lit).
    final n = widget.ads.length;
    _controller = PageController(
      viewportFraction: 0.86,
      initialPage: n > 1 ? _startPage - (_startPage % n) : _startPage,
    );
    _schedule();
  }

  @override
  void didUpdateWidget(covariant AdCarousel old) {
    super.didUpdateWidget(old);
    if (old.ads.length != widget.ads.length) {
      // The ad list changed length (one expired / was added): keep the dot in
      // step with the card actually showing.
      if (_count > 0 && _controller.hasClients) {
        _page = (_controller.page?.round() ?? _startPage) % _count;
      } else {
        _page = 0;
      }
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// (Re)starts the countdown to the next slide. No-op for 0–1 ads.
  void _schedule() {
    _timer?.cancel();
    if (!_moves) return;
    _timer = Timer(widget.interval, _advance);
  }

  void _pause() => _timer?.cancel();

  Future<void> _advance() async {
    if (!mounted || !_moves) return;
    // Tabs sit in an IndexedStack — don't animate while hidden.
    if (_controller.hasClients && TickerMode.valuesOf(context).enabled) {
      final current = _controller.page?.round() ?? _startPage;
      try {
        await _controller.animateToPage(
          current + 1,
          duration: widget.slideDuration,
          curve: Curves.easeInOut,
        );
      } catch (_) {
        // Interrupted by the user's own swipe — fine.
      }
    }
    if (mounted) _schedule();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ads = widget.ads;
    if (ads.isEmpty) return const SizedBox.shrink();

    // One ad: a still card, full width.
    if (!_moves) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 128,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter),
              child: _card(ads.first),
            ),
          ),
        ],
      );
    }

    final page = _page.clamp(0, ads.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 128,
          // A finger down anywhere on the strip pauses the auto-slide.
          child: Listener(
            onPointerDown: (_) => _pause(),
            onPointerUp: (_) => _schedule(),
            onPointerCancel: (_) => _schedule(),
            child: PageView.builder(
              key: const ValueKey('ad-pager'),
              controller: _controller,
              onPageChanged: (p) => setState(() => _page = p % ads.length),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: _card(ads[i % ads.length]),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.screenGutter),
          child: Row(
            children: List.generate(
              ads.length,
              (i) => AnimatedContainer(
                key: ValueKey('ad-dot-$i'),
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

  Widget _card(Advertisement ad) => PromoCard(
        title: ad.title,
        subtitle: ad.subtitle,
        dark: ad.isDark,
        imageUrl: ad.imageUrl,
        onTap: () => widget.onTap(ad),
      );
}

/// A promo strip card. Beyond the flat colour it carries a pair of very
/// faint concentric circles bleeding off the right edge — the subtle
/// interior shape the design uses so the cards don't read as plain boxes.
class PromoCard extends StatelessWidget {
  const PromoCard({
    super.key,
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
