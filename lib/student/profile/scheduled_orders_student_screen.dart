import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/models/order.dart';
import '../tracking/order_tracking_screen.dart';

final _scheduledOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final data = await client
      .from('orders')
      .select('*, vendors(name)')
      .eq('student_id', user.id)
      .not('scheduled_for', 'is', null)
      .inFilter('status', ['placed', 'preparing'])
      .order('scheduled_for', ascending: true);

  return data.map((m) => Order.fromMap(m)).toList();
});

/// Shows the student's upcoming scheduled orders with a live countdown.
class ScheduledOrdersStudentScreen extends ConsumerWidget {
  const ScheduledOrdersStudentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ordersAsync = ref.watch(_scheduledOrdersProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Scheduled Orders'),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
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
                    'Schedule an order from checkout to see it here.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
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
              theme: theme,
            ),
          );
        },
      ),
    );
  }
}

class _ScheduledOrderCard extends StatelessWidget {
  const _ScheduledOrderCard({required this.order, required this.theme});

  final Order order;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheduledFor = order.scheduledFor!;
    final now = DateTime.now();
    final diff = scheduledFor.difference(now);
    final isPast = diff.isNegative;
    final countdown = isPast
        ? 'Due now'
        : diff.inHours > 0
            ? '${diff.inHours}h ${diff.inMinutes % 60}m away'
            : '${diff.inMinutes}m away';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  order.shortId,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isPast ? AppColors.error : AppColors.info)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    countdown,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isPast ? AppColors.error : AppColors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (order.vendorName != null)
              Text('from ${order.vendorName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  )),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.schedule_outlined, size: 14),
                const SizedBox(width: 4),
                Text(
                  _formatDateTime(scheduledFor),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('₦${order.totalAmount.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: AppColors.emerald,
                      fontWeight: FontWeight.w700,
                    )),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => OrderTrackingScreen(order: order),
                    ),
                  ),
                  child: const Text('Track'),
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} at $h:$m';
  }
}
