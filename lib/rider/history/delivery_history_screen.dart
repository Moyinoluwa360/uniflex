import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../delivery/delivery_record.dart';
import '../services/rider_providers.dart';

class DeliveryHistoryScreen extends ConsumerWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(deliveryHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(deliveryHistoryProvider),
          ),
        ],
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppColors.error, size: 40),
                const SizedBox(height: AppSpacing.md),
                Text('Could not load history: $e',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => ref.invalidate(deliveryHistoryProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (records) {
          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.history_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('No deliveries yet',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Completed deliveries will appear here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl,
            ),
            itemCount: records.length,
            itemBuilder: (ctx, i) => _HistoryCard(record: records[i]),
          );
        },
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final DeliveryRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final typeLabel = record.orderType == 'around' ? 'Around' : 'Food';
    final typeColor = record.orderType == 'around'
        ? const Color(0xFF7C3AED)
        : AppColors.emerald;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            // Type icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                record.orderType == 'around'
                    ? Icons.directions_bike_outlined
                    : Icons.delivery_dining_outlined,
                color: typeColor,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record.shortId,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm - 2, vertical: 2),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.1),
                          borderRadius:
                              BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          typeLabel,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: typeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(record.completedAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                  if (record.deliveryLocation != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      record.deliveryLocation!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Amount + duration
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (record.orderTotal != null)
                  Text(
                    '₦${record.orderTotal!.toStringAsFixed(0)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.emerald,
                    ),
                  ),
                Text(
                  record.durationLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today ${_time(dt)}';
    if (diff.inDays == 1) return 'Yesterday ${_time(dt)}';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _time(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
