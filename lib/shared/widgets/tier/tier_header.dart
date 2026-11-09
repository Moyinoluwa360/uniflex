import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/tier_tokens.dart';
import '../avatar/app_avatar.dart';

/// The Profile header: a card (radius 24, padding 18) washed in the member's
/// tier colour, with a tier border, a tier-ringed avatar, the name (22/700),
/// `@nickname`, and a small outlined chip carrying the tier name.
///
/// An unknown or missing tier falls back to a plain surface (no tint).
class TierHeader extends StatelessWidget {
  const TierHeader({
    super.key,
    required this.tier,
    required this.name,
    required this.nickname,
    required this.initial,
  });

  final String? tier;
  final String name;
  final String nickname;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final brightness = Theme.of(context).brightness;
    final style = TierTokens.of(tier, brightness);
    final radius = BorderRadius.circular(AppRadius.cardLarge);
    final highlight = TierTokens.highlight(brightness);
    final chipColor = style?.text ?? c.textSecondary;
    final tierName = (tier ?? '').trim();

    return DecoratedBox(
      key: const ValueKey('tier-header'),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        border: Border.all(color: style?.border ?? c.border),
        boxShadow: c.cardShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (style != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: style.gradient),
                ),
              ),
            // 1px inner top highlight.
            Positioned(
              top: 0,
              left: AppRadius.cardLarge,
              right: AppRadius.cardLarge,
              height: 1,
              child: ColoredBox(color: highlight),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  AppAvatar(initial: initial, size: 64, tier: tier),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.greetingName(c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '@$nickname',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.meta(c),
                        ),
                        if (tierName.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm + 2),
                          DecoratedBox(
                            key: const ValueKey('tier-chip'),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              border: Border.all(
                                color: style?.border ?? c.borderStrong,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(AppIcons.award, size: 14, color: chipColor),
                                  const SizedBox(width: 5),
                                  Flexible(
                                    child: Text(
                                      tierName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppTypography.buttonSmall(chipColor)
                                          .copyWith(fontSize: 12.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
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
