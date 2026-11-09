import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/rider_providers.dart';
import 'rider_job.dart';
import '../../shared/widgets/buttons/app_button.dart';

/// Shown after the rider's delivery PIN is accepted (food and errands), in
/// place of the job screen simply vanishing. The time is the server's single
/// `completed_at`, shown in the phone's local time.
class DeliveryCompleteScreen extends ConsumerWidget {
  const DeliveryCompleteScreen({super.key, required this.jobId});

  /// Delivery-group id (food) or order id (errand).
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(riderHistoryItemProvider(jobId));
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: RetrySection(
                message: 'Delivery was confirmed, but we could not load the '
                    'summary.',
                onRetry: () => ref.invalidate(riderHistoryItemProvider(jobId)),
              ),
            ),
            data: (d) => DeliveryCompleteView(
              detail: d,
              onDone: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure rendering (what the widget test drives).
class DeliveryCompleteView extends StatelessWidget {
  const DeliveryCompleteView({
    super.key,
    required this.detail,
    required this.onDone,
  });

  final RiderJobDetail detail;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: context.colors.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_circle,
                key: const ValueKey('delivery-complete-icon'),
                color: context.colors.brandText,
                size: 56),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Delivery complete',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.lg),
          _Row(label: 'Order', value: detail.shortId),
          if (detail.customerName != null)
            _Row(label: 'Customer', value: detail.customerName!),
          if (detail.completedAt != null)
            _Row(
                label: 'Delivered at',
                value: formatLocalDateTime(detail.completedAt!)),
          if (detail.completedAt == null)
            Text('Time unavailable',
                style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: AppButton(
              label: 'Done',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onDone,
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
