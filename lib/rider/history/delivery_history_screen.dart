import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../jobs/rider_job.dart';
import '../jobs/rider_job_card.dart';
import '../services/rider_providers.dart';
import 'rider_history_detail_screen.dart';

/// History: ONE entry per checkout (completed or cancelled), newest first.
class DeliveryHistoryScreen extends ConsumerWidget {
  const DeliveryHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(riderHistoryProvider);
    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Delivery History',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(riderHistoryProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) {
          debugPrint('[RiderHistory] load error: $e');
          return RetrySection(
            message: 'Could not load history.',
            onRetry: () => ref.invalidate(riderHistoryProvider),
          );
        },
        data: (jobs) => RiderHistoryList(
          jobs: jobs,
          onOpen: (j) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => RiderHistoryDetailScreen(jobId: j.id),
          )),
        ),
      ),
    );
  }
}

class RiderHistoryList extends StatelessWidget {
  const RiderHistoryList({super.key, required this.jobs, required this.onOpen});

  final List<RiderJob> jobs;
  final void Function(RiderJob) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (jobs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_outlined,
                size: 56,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: AppSpacing.md),
            Text('No deliveries yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Completed and cancelled jobs will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        for (final j in jobs)
          RiderJobCard(
            key: ValueKey('history-${j.id}'),
            job: j,
            mode: RiderJobCardMode.history,
            onTap: () => onOpen(j),
          ),
      ],
    );
  }
}
