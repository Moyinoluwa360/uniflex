import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/saving_plan.dart';
import '../../shared/models/wallet_transaction.dart';
import '../../shared/services/saving_plan/saving_plan_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';

/// Saving Plan screen — lets the student set a spending budget for a
/// chosen period (Daily / Weekly / Monthly).
///
/// Shows:
///   • Current plan summary (if active): period, budget, spent, remaining
///   • Period picker + budget input (for creating or updating the plan)
///   • Budget History: order payments made in the current period
class SavingPlanScreen extends ConsumerStatefulWidget {
  const SavingPlanScreen({super.key});

  @override
  ConsumerState<SavingPlanScreen> createState() => _SavingPlanScreenState();
}

class _SavingPlanScreenState extends ConsumerState<SavingPlanScreen> {
  BudgetPeriod _selectedPeriod = BudgetPeriod.weekly;
  final _budgetController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _budgetController.dispose();
    super.dispose();
  }

  /// Pre-fill the form if an existing plan is loaded.
  void _populateFromPlan(SavingPlan plan) {
    if (_budgetController.text.isEmpty) {
      _selectedPeriod = plan.period;
      _budgetController.text = plan.budget.toStringAsFixed(0);
    }
  }

  Future<void> _savePlan() async {
    if (!_formKey.currentState!.validate()) return;

    final budget = double.parse(_budgetController.text.trim());
    await ref.read(savingPlanNotifierProvider.notifier).upsert(
          period: _selectedPeriod,
          budget: budget,
        );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving plan saved'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removePlan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove saving plan?'),
        content: const Text(
          'Your spending will no longer be tracked against a budget.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await ref.read(savingPlanNotifierProvider.notifier).deactivate();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Saving plan removed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(activeSavingPlanProvider);
    final notifierState = ref.watch(savingPlanNotifierProvider);
    final txAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saving Plan')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: planAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (plan) {
            if (plan != null) _populateFromPlan(plan);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Current plan summary ─────────────────────────────────
                if (plan != null) ...[
                  _PlanSummaryCard(plan: plan),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── Period picker ────────────────────────────────────────
                Text(
                  plan != null ? 'Update your plan' : 'Set a budget',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your wallet spending will be tracked against this budget. You\'ll be warned if you go over.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Period chips
                Row(
                  children: BudgetPeriod.values.map((p) {
                    final selected = _selectedPeriod == p;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          label: Text(p.label),
                          selected: selected,
                          onSelected: (_) =>
                              setState(() => _selectedPeriod = p),
                          selectedColor:
                              theme.colorScheme.primary.withValues(alpha: 0.15),
                          labelStyle: theme.textTheme.labelMedium?.copyWith(
                            color: selected
                                ? theme.colorScheme.primary
                                : null,
                            fontWeight: selected ? FontWeight.w600 : null,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: AppSpacing.md),

                // Budget amount
                Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _budgetController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    decoration: InputDecoration(
                      prefixText: '₦ ',
                      labelText: '${_selectedPeriod.label} budget',
                      hintText: '5000',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n < 100) {
                        return 'Enter at least ₦100';
                      }
                      return null;
                    },
                  ),
                ),

                const SizedBox(height: AppSpacing.md),

                PrimaryButton(
                  label: plan != null ? 'Update Plan' : 'Set Plan',
                  isLoading: notifierState.isLoading,
                  onPressed: _savePlan,
                ),

                if (plan != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed: _removePlan,
                      child: Text(
                        'Remove saving plan',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ],

                // ── Budget history ───────────────────────────────────────
                const SizedBox(height: AppSpacing.xl),
                Text('Budget history', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Order payments in your current plan period.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),

                txAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Could not load: $e'),
                  data: (txs) {
                    // Show only order-payment debits within the current period
                    final periodStart = plan?.periodStart ??
                        DateTime.now()
                            .toUtc()
                            .subtract(const Duration(days: 30));
                    final budgetTxs = txs
                        .where(
                          (t) =>
                              t.type == WalletTxType.debit &&
                              t.source == WalletTxSource.orderPayment &&
                              t.createdAt.isAfter(periodStart),
                        )
                        .toList();

                    if (budgetTxs.isEmpty) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Text(
                          'No spending yet this period.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      );
                    }

                    return Column(
                      children: budgetTxs.map((t) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.label,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(
                                '−₦${t.amount.toStringAsFixed(0)}',
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: AppColors.orange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: AppSpacing.xl),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Plan summary card ─────────────────────────────────────────────────────────

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.plan});

  final SavingPlan plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overBudget = plan.isOverBudget;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: overBudget
            ? AppColors.error.withValues(alpha: 0.06)
            : theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: overBudget
              ? AppColors.error.withValues(alpha: 0.3)
              : theme.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overBudget
                    ? Icons.warning_amber_rounded
                    : Icons.savings_outlined,
                size: 18,
                color: overBudget
                    ? AppColors.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                plan.periodLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: overBudget
                      ? AppColors.error
                      : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (overBudget) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Over budget',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _BudgetRow(
            label: 'Budget',
            value: '₦${plan.budget.toStringAsFixed(0)}',
            theme: theme,
          ),
          _BudgetRow(
            label: 'Spent',
            value: '₦${plan.spent.toStringAsFixed(0)}',
            theme: theme,
            valueColor: overBudget ? AppColors.error : AppColors.orange,
          ),
          _BudgetRow(
            label: 'Remaining',
            value: overBudget
                ? '−₦${(plan.spent - plan.budget).toStringAsFixed(0)}'
                : '₦${plan.remainingBudget.toStringAsFixed(0)}',
            theme: theme,
            valueColor:
                overBudget ? AppColors.error : AppColors.emerald,
            bold: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: (plan.spent / plan.budget).clamp(0.0, 1.0),
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                overBudget ? AppColors.error : AppColors.emerald,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({
    required this.label,
    required this.value,
    required this.theme,
    this.valueColor,
    this.bold = false,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final Color? valueColor;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(
                color:
                    theme.colorScheme.onSurface.withValues(alpha: 0.6),
              )),
          Text(
            value,
            style: (bold
                    ? theme.textTheme.labelMedium
                    : theme.textTheme.bodySmall)
                ?.copyWith(
              color: valueColor,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ],
      ),
    );
  }
}
