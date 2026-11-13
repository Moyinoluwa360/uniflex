import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/saving_plan.dart';
import '../../shared/models/wallet_transaction.dart';
import '../../shared/services/saving_plan/saving_plan_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cart/summary_row.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/tabs/app_segmented_tabs.dart';
import '../../shared/widgets/text/app_section_label.dart';
import '../../shared/utils/app_error_mapper.dart';

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
        content: Text('Spending budget saved'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _removePlan() async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Remove spending budget?',
      body: 'Your spending will no longer be tracked against a budget.',
      secondaryLabel: 'Cancel',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed != true || !mounted) return;

    await ref.read(savingPlanNotifierProvider.notifier).deactivate();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Spending budget removed'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final planAsync = ref.watch(activeSavingPlanProvider);
    final notifierState = ref.watch(savingPlanNotifierProvider);
    final txAsync = ref.watch(walletTransactionsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Spending budget'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: planAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text(AppErrorMapper.map(e))),
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
                AppSectionLabel(
                  plan != null ? 'Update your plan' : 'Set a budget',
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your wallet spending will be tracked against this budget. You\'ll be warned if you go over.',
                  style: AppTypography.meta(c),
                ),
                const SizedBox(height: AppSpacing.md),

                // Period picker
                AppSegmentedTabs(
                  labels: [for (final p in BudgetPeriod.values) p.label],
                  index: BudgetPeriod.values.indexOf(_selectedPeriod),
                  onChanged: (i) =>
                      setState(() => _selectedPeriod = BudgetPeriod.values[i]),
                ),

                const SizedBox(height: AppSpacing.md),

                // Budget amount
                Form(
                  key: _formKey,
                  child: AppTextField(
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

                AppButton(
                  label: plan != null ? 'Update Plan' : 'Set Plan',
                  icon: AppIcons.savings,
                  isLoading: notifierState.isLoading,
                  onPressed: _savePlan,
                ),

                if (plan != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: AppButton(
                      label: 'Remove spending budget',
                      variant: AppButtonVariant.quietDanger,
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed: _removePlan,
                    ),
                  ),
                ],

                // ── Budget history ───────────────────────────────────────
                const SizedBox(height: AppSpacing.xl),
                const AppSectionLabel('Budget history'),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Order payments in your current plan period.',
                  style: AppTypography.meta(c),
                ),
                const SizedBox(height: AppSpacing.sm),

                txAsync.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Could not load. ${AppErrorMapper.map(e)}'),
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
                              t.source.isSpending &&
                              t.createdAt.isAfter(periodStart),
                        )
                        .toList();

                    if (budgetTxs.isEmpty) {
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: AppSpacing.md),
                        child: Text(
                          'No spending yet this period.',
                          style: AppTypography.meta(c),
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
                                  style: AppTypography.meta(c),
                                ),
                              ),
                              Text(
                                Money.minus(t.amount),
                                style: AppTypography.tabular(
                                  AppTypography.meta(c).copyWith(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
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
    final c = context.colors;
    final overBudget = plan.isOverBudget;

    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  overBudget ? AppIcons.error : AppIcons.savings,
                  size: 18,
                  color: overBudget ? c.dangerText : c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  plan.periodLabel,
                  style: AppTypography.meta(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (overBudget) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Over budget',
                    style: AppTypography.caption(c).copyWith(
                      color: c.dangerText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SummaryRow(label: 'Budget', value: Money.format(plan.budget)),
            SummaryRow(label: 'Spent', value: Money.format(plan.spent)),
            SummaryRow(
              label: 'Remaining',
              value: overBudget
                  ? Money.minus(plan.spent - plan.budget)
                  : Money.format(plan.remainingBudget),
              valueColor: overBudget ? c.dangerText : c.brandText,
              bold: true,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Progress bar (8px)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (plan.spent / plan.budget).clamp(0.0, 1.0),
                backgroundColor: c.surfaceRaised,
                valueColor: AlwaysStoppedAnimation<Color>(
                  overBudget ? c.dangerText : c.brand,
                ),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
