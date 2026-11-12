import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/format/money.dart';

/// Admin view of all upcoming scheduled orders, ordered by scheduled_for
/// with a live countdown to each. Backed by Supabase Realtime so counts
/// and statuses update without a page refresh.
class AdminScheduledOrdersScreen extends ConsumerWidget {
  const AdminScheduledOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(scheduledOrdersProvider);

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Scheduled Orders',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: context.colors.brandText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  'Live',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: context.colors.brandText),
                ),
              ],
            ),
          ),
        ],
      ),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load scheduled orders.',
          onRetry: () => ref.invalidate(scheduledOrdersProvider),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 56,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('No scheduled orders',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Pre-orders placed by students appear here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: orders.length,
            itemBuilder: (ctx, i) => _ScheduledOrderCard(
              order: orders[i],
              onAdvance: () async {
                await ref
                    .read(adminServiceProvider)
                    .updateOrderStatus(orders[i].id, 'preparing');
                ref.invalidate(scheduledOrdersProvider);
                ref.invalidate(kitchenOrdersProvider);
              },
              onMarkReady: orders[i].status == OrderStatus.preparing
                  ? () async {
                      await ref
                          .read(adminServiceProvider)
                          .updateOrderStatus(orders[i].id, 'ready_for_pickup');
                      ref.invalidate(scheduledOrdersProvider);
                      ref.invalidate(kitchenOrdersProvider);
                    }
                  : null,
            ),
          );
        },
      ),
    );
  }
}

class _ScheduledOrderCard extends StatefulWidget {
  const _ScheduledOrderCard({
    required this.order,
    required this.onAdvance,
    this.onMarkReady,
  });

  final Order order;
  final VoidCallback onAdvance;

  /// Called when admin taps "Mark Ready for Pickup" on a preparing order.
  final VoidCallback? onMarkReady;

  @override
  State<_ScheduledOrderCard> createState() => _ScheduledOrderCardState();
}

class _ScheduledOrderCardState extends State<_ScheduledOrderCard> {
  late String _countdown;

  @override
  void initState() {
    super.initState();
    _updateCountdown();
    // Ticker that refreshes the countdown each second
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(_updateCountdown);
      return true;
    });
  }

  void _updateCountdown() {
    final scheduled = widget.order.scheduledFor;
    if (scheduled == null) {
      _countdown = '—';
      return;
    }
    final diff = scheduled.difference(DateTime.now());
    if (diff.isNegative) {
      _countdown = 'OVERDUE';
    } else if (diff.inHours >= 1) {
      _countdown =
          '${diff.inHours}h ${(diff.inMinutes % 60).toString().padLeft(2, '0')}m';
    } else if (diff.inMinutes >= 1) {
      _countdown =
          '${diff.inMinutes}m ${(diff.inSeconds % 60).toString().padLeft(2, '0')}s';
    } else {
      _countdown = '${diff.inSeconds}s';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final isOverdue = order.scheduledFor?.isBefore(DateTime.now()) ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(
          color: isOverdue ? context.colors.surfaceRaised : theme.dividerColor,
          width: isOverdue ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.shortId,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                // Live countdown badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.colors.surfaceRaised,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    _countdown,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isOverdue
                          ? context.colors.dangerText
                          : context.colors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            if (order.vendorName != null) ...[
              const SizedBox(height: 4),
              Text(
                order.vendorName!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                const Icon(Icons.schedule_outlined, size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(order.scheduledFor!),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            if (order.deliveryLocation != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.deliveryLocation!,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (order.isBulk) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'BULK',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: context.colors.statusAmber,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  Money.format(order.totalAmount),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: context.colors.brandText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (order.status == OrderStatus.placed)
                  AppButton(
                    label: 'Start Preparing',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: widget.onAdvance,
                  )
                else if (order.status == OrderStatus.preparing &&
                    widget.onMarkReady != null)
                  AppButton(
                    label: 'Mark Ready for Pickup',
                    variant: AppButtonVariant.primary,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: widget.onMarkReady,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
