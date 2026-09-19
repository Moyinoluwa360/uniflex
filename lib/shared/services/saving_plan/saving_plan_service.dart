import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/saving_plan.dart';

/// Service wrapping Supabase calls for the student saving plan.
///
/// Saving plan rows are managed directly by the authenticated client
/// (the RLS policies allow insert/update/delete on own rows). No RPC is
/// needed here because there is no money movement — spending is tracked
/// inside the order placement RPCs.
class SavingPlanService {
  const SavingPlanService(this._client);

  final SupabaseClient _client;

  /// Returns the active saving plan for the signed-in student, or null
  /// if no plan is set.
  Future<SavingPlan?> fetchActivePlan() async {
    final user = _client.auth.currentUser;
    if (user == null) return null;

    final row = await _client
        .from('saving_plans')
        .select()
        .eq('user_id', user.id)
        .eq('is_active', true)
        .maybeSingle();

    if (row == null) return null;
    return SavingPlan.fromMap(row);
  }

  /// Creates or updates the active saving plan for the signed-in student.
  /// Resets [spent] to 0 and anchors [periodStart] to the current
  /// period boundary whenever the plan is saved.
  Future<SavingPlan> upsertPlan({
    required BudgetPeriod period,
    required double budget,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Not signed in');

    final now = DateTime.now().toUtc();
    final periodStart = _periodAnchor(period, now);

    final row = await _client
        .from('saving_plans')
        .upsert(
          {
            'user_id': user.id,
            'period': period.rawValue,
            'budget': budget,
            'spent': 0,
            'period_start': periodStart.toIso8601String(),
            'is_active': true,
          },
          onConflict: 'user_id',
        )
        .select()
        .single();

    return SavingPlan.fromMap(row);
  }

  /// Deactivates the current saving plan.
  Future<void> deactivatePlan() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    await _client
        .from('saving_plans')
        .update({'is_active': false, 'updated_at': DateTime.now().toUtc().toIso8601String()})
        .eq('user_id', user.id);
  }

  /// Computes the start of the current period (day/week/month) in UTC.
  DateTime _periodAnchor(BudgetPeriod period, DateTime now) {
    return switch (period) {
      BudgetPeriod.daily => DateTime.utc(now.year, now.month, now.day),
      BudgetPeriod.weekly => _startOfWeek(now),
      BudgetPeriod.monthly => DateTime.utc(now.year, now.month),
    };
  }

  DateTime _startOfWeek(DateTime dt) {
    // ISO week starts on Monday (weekday == 1)
    final daysFromMonday = (dt.weekday - 1) % 7;
    final monday = dt.subtract(Duration(days: daysFromMonday));
    return DateTime.utc(monday.year, monday.month, monday.day);
  }
}
