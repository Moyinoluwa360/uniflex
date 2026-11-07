import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../jobs/errand_job_screen.dart';
import '../jobs/food_job_screen.dart';
import '../jobs/rider_job.dart';
import '../jobs/rider_job_card.dart';
import '../services/rider_providers.dart';

/// Jobs tab: the pool ONLY — jobs waiting to be accepted. Active work lives
/// on Home ("Active jobs"), finished work in History.
class JobPoolScreen extends ConsumerWidget {
  const JobPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poolAsync = ref.watch(riderPoolProvider);
    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Available Jobs',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text('Live',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: AppColors.emerald)),
              ],
            ),
          ),
        ],
      ),
      body: poolAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load jobs. Check your connection.',
          onRetry: () => ref.invalidate(riderPoolProvider),
        ),
        data: (pool) => JobPoolList(pool: pool),
      ),
    );
  }
}

/// The pool list itself (what the widget test drives): pool cards only —
/// there are no "active delivery / active errand" links here.
class JobPoolList extends StatelessWidget {
  const JobPoolList({super.key, required this.pool});

  final RiderPool pool;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (pool.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 48,
                color: theme.colorScheme.primary.withValues(alpha: 0.6)),
            const SizedBox(height: AppSpacing.md),
            Text('No jobs available', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'New orders will appear here automatically.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }
    final jobs = [...pool.groups, ...pool.errands];
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
            key: ValueKey('pool-${j.id}'),
            job: j,
            mode: RiderJobCardMode.pool,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => j.isFood
                  ? FoodJobScreen.fromPool(job: j)
                  : ErrandJobScreen.fromPool(job: j),
            )),
          ),
      ],
    );
  }
}
