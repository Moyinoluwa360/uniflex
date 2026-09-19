import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Standard rounded card surface. Wraps [Card] with the theme's radius/
/// border so every card in the app (food listing, order summary, rider
/// job, admin metric tile) looks like it belongs to the same system.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Card(
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) return card;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: card,
    );
  }
}
