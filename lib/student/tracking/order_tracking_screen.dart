import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../ordering/order_repository.dart';

/// Live order tracking — shows the current order status as a vertical
/// step timeline, refreshable. The data source is [orderByIdProvider]
/// (a FutureProvider) so swapping it for a Supabase realtime stream in
/// Phase 3 leaves the UI unchanged.
class OrderTrackingScreen extends ConsumerWidget {
  const OrderTrackingScreen({super.key, required this.order});

  /// Seed with the order at the point of navigation; refreshes from DB
  /// on every rebuild / manual refresh.
  final Order order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final liveAsync = ref.watch(orderByIdProvider(order.id));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Track Order ${order.shortId}',
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
          message: 'Could not load this order.',
          onRetry: () => ref.invalidate(orderByIdProvider(order.id)),
        ),
        data: (liveOrder) {
          final o = liveOrder ?? order;
          final steps = _buildSteps(o);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header card
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
                      if (o.vendorName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'from ${o.vendorName}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(o.status)
                                  .withValues(alpha: 0.15),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              o.status.label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _statusColor(o.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (o.estimatedTime != null)
                            Row(
                              children: [
                                const Icon(
                                  Icons.schedule_outlined,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  o.estimatedTime!,
                                  style: theme.textTheme.labelSmall,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: AppSpacing.lg),
                Text('Order progress', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.md),

                // Status timeline
                _StatusTimeline(steps: steps, currentStatus: o.status),

                const SizedBox(height: AppSpacing.xl),

                // Delivery info
                if (o.deliveryLocation != null) ...[
                  Text('Delivery to', style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          o.deliveryLocation!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ],

                // Assigned rider's contact — shown once one is assigned
                // (post-testing fixes, Section 12: the student previously
                // had no way to see who was delivering their order).
                if (o.riderId != null) ...[
                  Consumer(
                    builder: (context, ref, _) {
                      final riderInfoAsync =
                          ref.watch(orderRiderInfoProvider(o.id));
                      final info = riderInfoAsync.valueOrNull;
                      if (info == null) return const SizedBox.shrink();
                      final name = info['full_name'] as String?;
                      final phone = info['phone'] as String?;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(AppRadius.card),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.two_wheeler_outlined),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Your rider',
                                        style: theme.textTheme.labelSmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                        )),
                                    Text(name ?? 'Assigned',
                                        style: theme.textTheme.bodyMedium),
                                  ],
                                ),
                              ),
                              if (phone != null)
                                Text(phone, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],

                const SizedBox(height: AppSpacing.xl),

                // Delivery PIN — shown when a rider has been assigned and
                // the order is out for delivery or still pending pickup.
                if (o.isForDelivery &&
                    o.deliveryPin != null &&
                    !o.status.isTerminal) ...[
                  _TrackingPinCard(pin: o.deliveryPin!),
                  const SizedBox(height: AppSpacing.xl),
                ],

                Text('Total', style: theme.textTheme.titleSmall),
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

  Color _statusColor(OrderStatus s) {
    return switch (s) {
      OrderStatus.placed => AppColors.info,
      OrderStatus.preparing => AppColors.warning,
      OrderStatus.ready ||
      OrderStatus.readyForPickup =>
        AppColors.emerald,
      OrderStatus.outForDelivery => AppColors.orange,
      OrderStatus.completed => AppColors.emerald,
      OrderStatus.cancelled => AppColors.error,
    };
  }

  List<_Step> _buildSteps(Order o) {
    if (o.isAround) {
      return const [
        _Step(status: OrderStatus.placed, label: 'Request Placed'),
        _Step(status: OrderStatus.preparing, label: 'Rider on the Way'),
        _Step(status: OrderStatus.ready, label: 'Item Picked Up'),
        _Step(status: OrderStatus.outForDelivery, label: 'Out for Delivery'),
        _Step(status: OrderStatus.completed, label: 'Delivered'),
      ];
    }

    if (o.isForDelivery) {
      return const [
        _Step(status: OrderStatus.placed, label: 'Order Placed'),
        _Step(status: OrderStatus.preparing, label: 'Preparing'),
        _Step(status: OrderStatus.ready, label: 'Ready'),
        _Step(status: OrderStatus.outForDelivery, label: 'Out for Delivery'),
        _Step(status: OrderStatus.completed, label: 'Delivered'),
      ];
    }

    // Pickup
    return const [
      _Step(status: OrderStatus.placed, label: 'Order Placed'),
      _Step(status: OrderStatus.preparing, label: 'Preparing'),
      _Step(status: OrderStatus.readyForPickup, label: 'Ready for Pickup'),
      _Step(status: OrderStatus.completed, label: 'Picked Up'),
    ];
  }
}

class _Step {
  const _Step({required this.status, required this.label});
  final OrderStatus status;
  final String label;
}

class _StatusTimeline extends StatelessWidget {
  const _StatusTimeline({
    required this.steps,
    required this.currentStatus,
  });

  final List<_Step> steps;
  final OrderStatus currentStatus;

  bool _isDone(OrderStatus step) {
    // Find the index of the current status in the steps list
    final stepValues = steps.map((s) => s.status).toList();
    final currentIdx = stepValues.indexOf(currentStatus);
    final stepIdx = stepValues.indexOf(step);
    if (currentIdx < 0 || stepIdx < 0) return false;
    return stepIdx <= currentIdx;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final done = _isDone(step.status);
        final isCurrent = step.status == currentStatus;
        final isLast = i == steps.length - 1;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Timeline column
            SizedBox(
              width: 36,
              child: Column(
                children: [
                  // Dot
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
                        ? const Icon(
                            Icons.check,
                            color: AppColors.pureWhite,
                            size: 16,
                          )
                        : null,
                  ),
                  // Connector line
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
            // Label
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                step.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight:
                      isCurrent ? FontWeight.w600 : FontWeight.w400,
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

/// PIN reminder shown on the tracking screen while a delivery is active.
class _TrackingPinCard extends StatelessWidget {
  const _TrackingPinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.emerald, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Your Delivery PIN',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied')),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  pin,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.copy_outlined,
                    size: 16, color: AppColors.emerald),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Show this to your rider at the door.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
