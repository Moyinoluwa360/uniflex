import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/local_time.dart';
import 'rider_job.dart';

enum RiderJobCardMode { pool, active, history }

/// One card = one checkout. Used by the Jobs tab, the Active jobs lists and
/// History so a job always looks the same. Shows no fees.
class RiderJobCard extends StatelessWidget {
  const RiderJobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.mode = RiderJobCardMode.pool,
  });

  final RiderJob job;
  final VoidCallback onTap;
  final RiderJobCardMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final accent =
        job.isFood ? context.colors.brandText : context.colors.textSecondary;

    final subtitle = job.isFood
        ? (job.vendorNames.isEmpty
            ? 'Food delivery'
            : job.vendorNames.join(' · '))
        : [
            if (job.category != null) job.category!,
            if (job.itemDescription != null) job.itemDescription!,
          ].join(' · ');

    final String? timeLine = switch (mode) {
      RiderJobCardMode.history => job.endedAt == null
          ? null
          : '${job.wasCancelled ? 'Cancelled' : 'Delivered'} '
              '${formatLocalDateTime(job.endedAt!)}',
      RiderJobCardMode.active => job.acceptedAt == null
          ? null
          : 'Accepted ${formatLocalRelative(job.acceptedAt!)}',
      RiderJobCardMode.pool =>
        job.createdAt == null ? null : formatLocalRelative(job.createdAt!),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      job.isFood ? 'FOOD' : 'ERRAND',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (job.isGift) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      key: const ValueKey('gift-tag'),
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceRaised,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        'GIFT',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: context.colors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(job.shortId,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (mode == RiderJobCardMode.history && job.wasCancelled)
                    Text(
                      job.cancelledByStudent
                          ? 'Cancelled by customer'
                          : 'Cancelled',
                      key: const ValueKey('cancelled-label'),
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: context.colors.dangerText,
                          fontWeight: FontWeight.w600),
                    )
                  else
                    const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium),
              ],
              if (job.isFood && job.stopCount > 1) ...[
                const SizedBox(height: 2),
                Text('${job.stopCount} vendors',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              ],
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(job.deliveryLocation ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                ],
              ),
              if (timeLine != null) ...[
                const SizedBox(height: 2),
                Text(timeLine,
                    style: theme.textTheme.labelSmall?.copyWith(color: muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
