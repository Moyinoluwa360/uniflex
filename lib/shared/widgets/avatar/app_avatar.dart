import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../theme/tier_tokens.dart';

/// A circle in `surfaceRaised` with a 1px strong border and a bold initial.
/// Sizes 40 and 64. Pass [tier] for the 2px tier ring.
class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.initial,
    this.size = 40,
    this.tier,
  });

  final String initial;

  /// 40 or 64.
  final double size;

  /// Membership tier name ('Bronze' ...). Unknown/null = no ring.
  final String? tier;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = TierTokens.of(tier, Theme.of(context).brightness);
    final letter = initial.trim().isEmpty
        ? '?'
        : initial.trim().characters.first.toUpperCase();

    final core = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        shape: BoxShape.circle,
        border: Border.all(color: c.borderStrong),
      ),
      child: Text(
        letter,
        style: AppTypography.greetingName(c.textPrimary).copyWith(
          fontSize: size >= 64 ? 26 : 16,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    if (style == null) return core;
    // Ring: 2px tier-coloured circle around the avatar, 2px gap.
    return Container(
      key: const ValueKey('avatar-ring'),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: style.ring, width: 2),
      ),
      child: core,
    );
  }
}
