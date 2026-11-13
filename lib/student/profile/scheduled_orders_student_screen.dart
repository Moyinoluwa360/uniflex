import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/models/order.dart';
import '../tracking/order_tracking_screen.dart';
import '../../shared/utils/app_error_mapper.dart';

final _scheduledOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final data = await client
      .from('orders')
      .select('*, vendors(name)')
      .eq('student_id', user.id)
      .not('scheduled_for', 'is', null)
      .inFilter('status', ['placed', 'preparing']).order('scheduled_for',
          ascending: true);

  return data.map((m) => Order.fromMap(m)).toList();
});

/// Shows the student's upcoming scheduled orders with a live countdown.
class ScheduledOrdersStudentScreen extends ConsumerWidget {
  const ScheduledOrdersStudentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = context.colors;
    final ordersAsync = ref.watch(_scheduledOrdersProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Scheduled Orders'),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load. ${AppErrorMapper.map(e)}')),
        data: (orders) {
          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.clock, size: 48, color: c.textTertiary),
                  const SizedBox(height: AppSpacing.md),
                  Text('No scheduled orders',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Schedule an order from checkout to see it here.',
                    style: AppTypography.meta(c),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: orders.length,
            itemBuilder: (ctx, i) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
              child: _ScheduledOrderCard(order: orders[i], theme: theme),
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

    final c = context.colors;
    return AppCard(
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
              AppStatusLabel(
                tone: isPast ? StatusTone.cancelled : StatusTone.waiting,
                text: countdown,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (order.vendorName != null)
            Text('from ${order.vendorName}', style: AppTypography.meta(c)),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(AppIcons.clock, size: 14, color: c.textTertiary),
              const SizedBox(width: 4),
              Text(
                _formatDateTime(scheduledFor),
                style: AppTypography.meta(c),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(Money.format(order.totalAmount),
                  style: AppTypography.tabular(theme.textTheme.titleSmall!
                      .copyWith(fontWeight: FontWeight.w700))),
              AppButton(
                label: 'Track',
                variant: AppButtonVariant.text,
                size: AppButtonSize.small,
                expand: false,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingScreen(order: order),
                  ),
                ),
              ),
            ],
          ),
        ],
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} at $h:$m';
  }
}
