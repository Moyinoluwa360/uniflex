import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/saving_plan.dart';
import '../supabase/supabase_providers.dart';
import 'saving_plan_service.dart';

// ---------------------------------------------------------------------------
// Service provider
// ---------------------------------------------------------------------------

final savingPlanServiceProvider = Provider<SavingPlanService>((ref) {
  return SavingPlanService(ref.watch(supabaseClientProvider));
});

// ---------------------------------------------------------------------------
// Read provider
// ---------------------------------------------------------------------------

/// The active saving plan for the signed-in student, or null if none is set.
/// Refreshed by calling `ref.invalidate(activeSavingPlanProvider)`.
final activeSavingPlanProvider = FutureProvider<SavingPlan?>((ref) async {
  final service = ref.watch(savingPlanServiceProvider);
  return service.fetchActivePlan();
});

// ---------------------------------------------------------------------------
// Write notifier
// ---------------------------------------------------------------------------

/// State for the saving plan notifier — mirrors [AsyncValue] but exposes
/// the result type we actually care about: the upserted [SavingPlan].
class SavingPlanNotifier extends AsyncNotifier<SavingPlan?> {
  @override
  Future<SavingPlan?> build() async {
    final service = ref.watch(savingPlanServiceProvider);
    return service.fetchActivePlan();
  }

  Future<void> upsert({
    required BudgetPeriod period,
    required double budget,
  }) async {
    state = const AsyncLoading();
    final service = ref.read(savingPlanServiceProvider);
    state = await AsyncValue.guard(
      () => service.upsertPlan(period: period, budget: budget),
    );
    // Keep the read provider in sync
    ref.invalidate(activeSavingPlanProvider);
  }

  Future<void> deactivate() async {
    state = const AsyncLoading();
    final service = ref.read(savingPlanServiceProvider);
    await service.deactivatePlan();
    state = const AsyncData(null);
    ref.invalidate(activeSavingPlanProvider);
  }
}

final savingPlanNotifierProvider =
    AsyncNotifierProvider<SavingPlanNotifier, SavingPlan?>(
  SavingPlanNotifier.new,
);
