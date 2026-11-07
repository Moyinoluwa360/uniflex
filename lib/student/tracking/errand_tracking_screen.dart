import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../ordering/order_repository.dart';

/// Simplified tracking screen for errand orders.
///
/// Shows a basic status timeline (placed → rider assigned → on the way → done),
/// rider name with Call and WhatsApp buttons once a rider is assigned,
/// and the delivery PIN. No sourcing, adjust-order, or final-payment steps.
class ErrandTrackingScreen extends ConsumerWidget {
  const ErrandTrackingScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final liveAsync = ref.watch(orderByIdProvider(order.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Errand ${order.shortId}',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(orderByIdProvider(order.id)),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: liveAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load this errand.',
          onRetry: () => ref.invalidate(orderByIdProvider(order.id)),
        ),
        data: (liveOrder) {
          final o = liveOrder ?? order;
          final statusColor = _statusColor(o.status);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header card ─────────────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.shortId,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Errand request',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          _errandLabel(o.status),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),

                // ── Timeline ────────────────────────────────────────────
                Text('Progress', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),
                _ErrandTimeline(status: o.status),

                const SizedBox(height: AppSpacing.xl),

                // ── Rider contact (once assigned) ────────────────────────
                if (o.riderId != null) ...[
                  Text('Your rider', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Consumer(
                    builder: (ctx, cref, _) {
                      final riderInfoAsync =
                          cref.watch(orderRiderInfoProvider(o.id));
                      final info = riderInfoAsync.valueOrNull;
                      if (info == null) return const SizedBox.shrink();

                      final name = info['full_name'] as String?;
                      final phone = info['phone'] as String?;

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.two_wheeler_outlined,
                                    size: 20),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  name ?? 'Assigned',
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                            if (phone != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.phone_outlined,
                                          size: 16),
                                      label: const Text('Call'),
                                      onPressed: () async {
                                        final uri = Uri.parse('tel:$phone');
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(uri);
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.chat_outlined,
                                          size: 16),
                                      label: const Text('WhatsApp'),
                                      onPressed: () async {
                                        final normalized = phone.replaceAll(
                                            RegExp(r'[^\d]'), '');
                                        final uri = Uri.parse(
                                            'https://wa.me/$normalized');
                                        if (await canLaunchUrl(uri)) {
                                          await launchUrl(
                                            uri,
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Delivery PIN ─────────────────────────────────────────
                if (o.deliveryPin != null && !o.status.isTerminal) ...[
                  Text('Delivery PIN', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                          color: AppColors.emerald.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          o.deliveryPin!,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: AppColors.emerald,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 8,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Show this to your rider to confirm delivery.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                // ── Fee ─────────────────────────────────────────────────
                Text('Fee', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '₦${o.totalAmount.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(OrderStatus s) => switch (s) {
        OrderStatus.placed => AppColors.info,
        OrderStatus.beingSourced => AppColors.warning,
        OrderStatus.outForDelivery => AppColors.orange,
        OrderStatus.completed => AppColors.emerald,
        OrderStatus.cancelled => AppColors.error,
        _ => AppColors.info,
      };

  /// Errand-specific status labels.
  String _errandLabel(OrderStatus s) => switch (s) {
        OrderStatus.placed => 'Errand placed',
        OrderStatus.beingSourced => 'Rider assigned',
        OrderStatus.outForDelivery => 'On the way',
        OrderStatus.completed => 'Done',
        OrderStatus.cancelled => 'Cancelled',
        _ => s.label,
      };
}

/// Four-step errand timeline:
/// Placed → Rider Assigned → On the Way → Done.
class _ErrandTimeline extends StatelessWidget {
  const _ErrandTimeline({required this.status});

  final OrderStatus status;

  static const _steps = [
    (status: OrderStatus.placed, label: 'Errand placed'),
    (status: OrderStatus.beingSourced, label: 'Rider assigned'),
    (status: OrderStatus.outForDelivery, label: 'On the way'),
    (status: OrderStatus.completed, label: 'Done'),
  ];

  int _currentIndex() => switch (status) {
        OrderStatus.placed => 0,
        OrderStatus.beingSourced => 1,
        OrderStatus.outForDelivery => 2,
        OrderStatus.completed => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentIdx = _currentIndex();

    return Column(
      children: List.generate(_steps.length, (i) {
        final step = _steps[i];
        final done = i <= currentIdx;
        final isCurrent = i == currentIdx;
        final isLast = i == _steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.emerald
                          : theme.colorScheme.surfaceContainerHighest,
                      border: isCurrent
                          ? Border.all(color: AppColors.emerald, width: 2)
                          : null,
                    ),
                    child: done
                        ? const Icon(Icons.check,
                            color: AppColors.pureWhite, size: 16)
                        : null,
                  ),
                  if (!isLast)
                    Container(
                      width: 2,
                      height: 36,
                      color: done
                          ? AppColors.emerald.withValues(alpha: 0.4)
                          : theme.colorScheme.outline,
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                step.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: done
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}
