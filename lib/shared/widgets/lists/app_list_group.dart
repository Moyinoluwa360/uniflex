import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../cards/app_card.dart';
import '../buttons/app_tappable.dart';

/// A card of [AppListRow]s separated by hairline dividers.
class AppListGroup extends StatelessWidget {
  const AppListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(height: 1, thickness: 1, color: c.border));
      }
      rows.add(children[i]);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: rows,
        ),
      ),
    );
  }
}

/// One row of an [AppListGroup]: min height 56, a plain 22px icon (no
/// coloured box), title 16/500, optional subtitle 12.5, and a chevron or a
/// custom trailing widget.
class AppListRow extends StatelessWidget {
  const AppListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leadingIcon,
    this.trailing,
    this.showChevron = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData? leadingIcon;

  /// Replaces the chevron.
  final Widget? trailing;

  /// Chevron shown when [onTap] is set and no [trailing] is given.
  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final end = trailing ??
        (onTap != null && showChevron
            ? Icon(AppIcons.chevronRight,
                size: AppIconSize.small, color: c.textTertiary)
            : null);

    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.listRowMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon,
                  size: AppIconSize.regular, color: c.textSecondary),
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: AppTypography.body(c)),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!, style: AppTypography.caption(c)),
                    ),
                ],
              ),
            ),
            if (end != null) ...[
              const SizedBox(width: AppSpacing.sm),
              end,
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return row;
    return AppTappable(onTap: onTap, child: row);
  }
}
