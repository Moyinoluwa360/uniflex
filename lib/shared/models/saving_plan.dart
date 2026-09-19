/// A row from the `saving_plans` table.
///
/// Each student has at most one active saving plan (enforced by the
/// `user_id unique` constraint). The plan tracks spending against a
/// self-set budget for the current [period]. The [spent] counter is
/// reset lazily the next time a payment is processed after the period
/// boundary passes (handled inside the `place_food_order_with_payment`
/// and `place_around_with_payment` Postgres RPCs).
class SavingPlan {
  const SavingPlan({
    required this.id,
    required this.userId,
    required this.period,
    required this.budget,
    required this.spent,
    required this.periodStart,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SavingPlan.fromMap(Map<String, dynamic> map) {
    return SavingPlan(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      period: BudgetPeriod.fromString(map['period'] as String),
      budget: (map['budget'] as num).toDouble(),
      spent: (map['spent'] as num).toDouble(),
      periodStart: DateTime.parse(map['period_start'] as String),
      isActive: map['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  final String id;
  final String userId;
  final BudgetPeriod period;
  final double budget;
  final double spent;
  final DateTime periodStart;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get remainingBudget => (budget - spent).clamp(0.0, double.infinity);
  bool get isOverBudget => spent > budget;

  /// Human-readable period label, e.g. "Daily budget".
  String get periodLabel => switch (period) {
        BudgetPeriod.daily => 'Daily budget',
        BudgetPeriod.weekly => 'Weekly budget',
        BudgetPeriod.monthly => 'Monthly budget',
      };
}

enum BudgetPeriod {
  daily,
  weekly,
  monthly;

  static BudgetPeriod fromString(String s) => switch (s) {
        'weekly' => weekly,
        'monthly' => monthly,
        _ => daily,
      };

  String get rawValue => switch (this) {
        daily => 'daily',
        weekly => 'weekly',
        monthly => 'monthly',
      };

  String get label => switch (this) {
        daily => 'Daily',
        weekly => 'Weekly',
        monthly => 'Monthly',
      };
}
