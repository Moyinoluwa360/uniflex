import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// One notification inside an `AppListGroup`.
///
/// Unread = an 8px `brand` dot and a 16/600 `textPrimary` title. Read = no dot
/// and a 16/500 `textSecondary` title. The icon is a plain 22px glyph (no
/// coloured circle).
class NotificationRow extends StatelessWidget {
  const NotificationRow({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.timeText,
    required this.unread,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final String timeText;
  final bool unread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleStyle = AppTypography.body(c).copyWith(
      fontWeight: unread ? FontWeight.w600 : FontWeight.w500,
      color: unread ? c.textPrimary : c.textSecondary,
    );
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpacing.listRowMin),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md - 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon, size: 22, color: c.textSecondary),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: titleStyle),
                  const SizedBox(height: 2),
                  Text(body, style: AppTypography.meta(c)),
                  const SizedBox(height: 6),
                  Text(timeText, style: AppTypography.caption(c)),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  key: const ValueKey('unread-dot'),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: c.brand,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
