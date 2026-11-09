import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/order_breakdown/order_breakdown_widget.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../jobs/rider_job.dart';
import '../services/rider_providers.dart';

/// Read-only details of a finished job: order ID, times, the shared item
/// breakdown, customer name and location. Phone and email are NOT shown once
/// the job has ended (owner decision, Pack 4B) and the server does not send
/// them; no matric number or fees either.
class RiderHistoryDetailScreen extends ConsumerWidget {
  const RiderHistoryDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(riderHistoryItemProvider(jobId));
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Job details'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[RiderHistoryDetail] load error: $e');
          return RetrySection(
            message: 'Could not load job details.',
            onRetry: () => ref.invalidate(riderHistoryItemProvider(jobId)),
          );
        },
        data: (d) => RiderHistoryDetailView(
          detail: d,
          // The same breakdown the pool, active job, Admin and student use.
          breakdown: d.kind == RiderJobKind.food
              ? OrderBreakdown(orderId: d.id)
              : null,
        ),
      ),
    );
  }
}

/// Pure rendering (what the widget test drives).
class RiderHistoryDetailView extends StatelessWidget {
  const RiderHistoryDetailView(
      {super.key, required this.detail, this.breakdown});

  final RiderJobDetail detail;
  final Widget? breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = detail;
    final cancelled = d.wasCancelled;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: (cancelled
                    ? context.colors.dangerText
                    : context.colors.brandText)
                .withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Row(
            children: [
              Icon(cancelled ? Icons.cancel_outlined : Icons.check_circle,
                  color: cancelled
                      ? context.colors.dangerText
                      : context.colors.brandText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  cancelled
                      ? (d.cancelledByStudent
                          ? 'Cancelled by customer'
                          : 'Cancelled')
                      : 'Delivered',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cancelled
                        ? context.colors.dangerText
                        : context.colors.brandText,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _Line(label: 'Order ID', value: d.shortId),
        if (d.customerName != null)
          _Line(label: 'Customer', value: d.customerName!),
        if (d.deliveryLocation != null)
          _Line(label: 'Drop-off', value: d.deliveryLocation!),
        if (d.acceptedAt != null)
          _Line(label: 'Accepted', value: formatLocalDateTime(d.acceptedAt!)),
        if (!cancelled && d.completedAt != null)
          _Line(label: 'Delivered', value: formatLocalDateTime(d.completedAt!)),
        if (cancelled && d.cancelledAt != null)
          _Line(label: 'Cancelled', value: formatLocalDateTime(d.cancelledAt!)),
        if (d.kind == RiderJobKind.food && d.amount != null)
          _Line(
              label: 'Items total', value: '₦${d.amount!.toStringAsFixed(0)}'),
        if (d.kind == RiderJobKind.errand) ...[
          if (d.category != null) _Line(label: 'Category', value: d.category!),
          if (d.itemDescription != null)
            _Line(label: 'Errand', value: d.itemDescription!),
          if (d.pickupLocation != null)
            _Line(label: 'Pickup', value: d.pickupLocation!),
        ],
        if (breakdown != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Order items',
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.sm),
          breakdown!,
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
