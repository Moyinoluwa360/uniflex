import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// A bold, clearly-boxed accordion card — the standard collapsible section
/// component used on the vendor page (Drinks, Others), inside each pack
/// (Meals, Proteins/Toppings), and in the cart (one section per vendor when
/// there are multiple vendors).
///
/// [leading]        — A pre-built 40×40 widget (icon in tinted square or
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
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget child;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final borderColor = isExpanded
        ? AppColors.emerald
        : theme.colorScheme.outline.withValues(alpha: isDark ? 0.3 : 0.2);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.xs,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: isExpanded
              ? AppColors.emerald.withValues(alpha: isDark ? 0.07 : 0.03)
              : (theme.cardTheme.color ?? theme.colorScheme.surface),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: borderColor, width: isExpanded ? 1.5 : 1.0),
          boxShadow: (isExpanded || isDark)
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.card),
          clipBehavior: Clip.antiAlias,
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
                              Text(
                                title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.55),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (trailingAction != null) ...[
                          trailingAction!,
                          const SizedBox(width: AppSpacing.xs),
                        ],
                        // Chevron circle ─────────────────────────────────
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isExpanded
                                  ? AppColors.emerald.withValues(alpha: 0.12)
                                  : theme.colorScheme.surfaceContainerHighest,
                            ),
                            child: Center(
                              child: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0,
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  Icons.expand_more_rounded,
                                  size: 20,
                                  color: isExpanded
                                      ? AppColors.emerald
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                ),
                              ),
                            ),
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
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: borderColor.withValues(alpha: 0.4),
                            ),
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

/// Builds the standard 40×40 icon-in-rounded-square leading widget for
/// [AppAccordionCard].
Widget buildAccordionLeadingIcon({
  required BuildContext context,
  required IconData icon,
  Color? color,
}) {
  final c = color ?? Theme.of(context).colorScheme.primary;
  return Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Icon(icon, color: c, size: 22),
  );
}
