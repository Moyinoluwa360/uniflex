import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/rider_providers.dart';
import 'errand_job_screen.dart';
import 'food_job_screen.dart';
import 'rider_job.dart';
import 'rider_job_card.dart';

/// "Active food deliveries" or "Active errands": one card per checkout.
/// Tapping a card opens the job screen (customer, order ID, item breakdown).
class ActiveJobsScreen extends ConsumerWidget {
  const ActiveJobsScreen({super.key, required this.kind});

  final RiderJobKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(riderActiveJobsProvider);
    return Scaffold(
      appBar: UniflexAppBar(
        title: kind == RiderJobKind.food
            ? 'Active food deliveries'
            : 'Active errands',
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load your active jobs.',
          onRetry: () => ref.invalidate(riderActiveJobsProvider),
        ),
        data: (jobs) => ActiveJobsList(
          kind: kind,
          jobs: jobs.where((j) => j.kind == kind).toList(),
          onOpen: (j) => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => j.isFood
                ? FoodJobScreen.active(groupId: j.id)
                : ErrandJobScreen.active(orderId: j.id),
          )),
        ),
      ),
    );
  }
}

/// The list + its per-kind empty state (what the widget test drives).
class ActiveJobsList extends StatelessWidget {
  const ActiveJobsList({
    super.key,
    required this.kind,
    required this.jobs,
    required this.onOpen,
  });

  final RiderJobKind kind;
  final List<RiderJob> jobs;
  final void Function(RiderJob) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (jobs.isEmpty) {
      final food = kind == RiderJobKind.food;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(food ? Icons.delivery_dining : Icons.directions_run,
                  size: 48,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
              const SizedBox(height: AppSpacing.md),
              Text(
                food ? 'No active food deliveries' : 'No active errands',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Jobs you accept will show here.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
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
            key: ValueKey('active-${j.id}'),
            job: j,
            mode: RiderJobCardMode.active,
            onTap: () => onOpen(j),
          ),
      ],
    );
  }
}

/// Bottom sheet shown when the rider has BOTH kinds active.
Future<void> showActiveJobsChooser(
  BuildContext context, {
  required int food,
  required int errands,
}) {
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius:
          BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (ctx) => ActiveJobsChooser(
      food: food,
      errands: errands,
      onPick: (kind) {
        Navigator.of(ctx).pop();
        openActiveJobsList(context, kind);
      },
    ),
  );
}

void openActiveJobsList(BuildContext context, RiderJobKind kind) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => ActiveJobsScreen(kind: kind)),
  );
}

class ActiveJobsChooser extends StatelessWidget {
  const ActiveJobsChooser({
    super.key,
    required this.food,
    required this.errands,
    required this.onPick,
  });

  final int food;
  final int errands;
  final void Function(RiderJobKind) onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active jobs',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              key: const ValueKey('chooser-food'),
              leading:
                  Icon(Icons.delivery_dining, color: context.colors.brandText),
              title: const Text('Active food deliveries'),
              trailing: Text('$food'),
              onTap: () => onPick(RiderJobKind.food),
            ),
            ListTile(
              key: const ValueKey('chooser-errands'),
              leading: Icon(Icons.directions_run,
                  color: context.colors.textSecondary),
              title: const Text('Active errands'),
              trailing: Text('$errands'),
              onTap: () => onPick(RiderJobKind.errand),
            ),
          ],
        ),
      ),
    );
  }
}
