import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';

/// A bold, clearly-boxed accordion card — the standard collapsible section
/// component used on the vendor page (Drinks, Others), inside each pack
/// (Meals, Proteins/Toppings), and in the cart (one section per vendor when
/// there are multiple vendors).
///
/// [leading]        — A pre-built 40×40 widget (icon in icon or
///                    vendor image). Build with [buildAccordionLeadingIcon]
///                    for icon sections, or wrap an AppImage for the cart.
/// [title]          — Primary label (~18 sp, bold).
/// [subtitle]       — Secondary label (item count, optional subtotal). Muted.
/// [isExpanded]     — Whether this card is currently open.
/// [onTap]          — Toggle callback. The parent manages which card is open
///                    so only one is open at a time within a group.
/// [child]          — Content shown when expanded. Animated with AnimatedSize.
/// [trailingAction] — Optional widget before the chevron (e.g. remove-vendor
///                    button). Absorbs its own gesture and does not fire [onTap].
class AppAccordionCard extends StatelessWidget {
  const AppAccordionCard({
    super.key,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.isExpanded,
    required this.onTap,
    required this.child,
    this.trailingAction,
    this.outerPadding,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;
  final Widget? trailingAction;

  /// Space around the card. Defaults to the standard screen gutter; pass
  /// [EdgeInsets] (e.g. vertical only) when the card sits inside another
  /// padded container such as a vendor accordion or a ListView.
  final EdgeInsetsGeometry? outerPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const radius = AppRadius.card;

    // A plain AppCard: surface + hairline border. Open = `borderStrong`
    // (no green tint, no glow).
    return Padding(
      padding: outerPadding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenGutter,
            vertical: AppSpacing.xs,
          ),
      child: AppCard(
        padding: EdgeInsets.zero,
        strongBorder: isExpanded,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header (tap target) ────────────────────────────────────
              InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        leading,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(title, style: AppTypography.title(c)),
                              const SizedBox(height: 2),
                              Text(subtitle, style: AppTypography.meta(c)),
                            ],
                          ),
                        ),
                        if (trailingAction != null) ...[
                          trailingAction!,
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          child: Icon(
                            AppIcons.chevronDown,
                            size: AppIconSize.regular,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // ── Expanded content ────────────────────────────────────────
              ClipRect(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Divider(height: 1, thickness: 1, color: c.border),
                            child,
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The accordion's leading icon: a plain 22px glyph in textSecondary — no
/// tinted tile behind it. ([color] is accepted only so existing call sites
/// still compile; it is ignored by design.)
Widget buildAccordionLeadingIcon({
  required BuildContext context,
  required IconData icon,
  Color? color,
}) {
  return SizedBox(
    width: 40,
    height: 40,
    child: Icon(
      icon,
      size: AppIconSize.regular,
      color: context.colors.textSecondary,
    ),
  );
}
