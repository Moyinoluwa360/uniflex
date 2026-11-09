import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// THE card: plain `surface`, 1px `border`, radius 20 (24 with [large]).
/// No shadow in dark, a hairline shadow in light. **No tint or colour
/// options on purpose** — a card that needs to stand out uses a stronger
/// border ([strongBorder]) or content, never a coloured fill.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.cardPadding),
    this.onTap,
    this.large = false,
    this.strongBorder = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Radius 24 instead of 20 (wallet card, tier header).
  final bool large;

  /// Uses `borderStrong` (e.g. an open accordion) instead of `border`.
  final bool strongBorder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius =
        BorderRadius.circular(large ? AppRadius.cardLarge : AppRadius.card);
    final body = Padding(padding: padding, child: child);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: Border.all(color: strongBorder ? c.borderStrong : c.border),
        boxShadow: c.cardShadow,
      ),
      child: onTap == null
          ? body
          : Material(
              color: Colors.transparent,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, borderRadius: radius, child: body),
            ),
    );
  }
}
