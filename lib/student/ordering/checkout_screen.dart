import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import 'cart_provider.dart';
import 'order_confirmation_screen.dart';
import 'order_repository.dart';
import 'pack_allocation_screen.dart';

/// Checkout — steps 6 and 7 of the ordering flow:
///   step 6: pickup / campus delivery / hostel room delivery
///   step 7: delivery location (shown for delivery types)
///   step 7b: schedule date/time (optional)
///
/// Post-testing fixes, Section 11: if the cart has any pack-requiring
/// items, a "Packing" section asks the student up front whether they
/// want packs, so the total shown by the time they reach Confirm is
/// already accurate.
///
/// Step 8 (payment): gates on the transaction PIN (Section 6), then
/// checks the wallet balance and calls [place_food_order_with_payment]
/// RPC which atomically deducts the wallet and creates the order.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  // 'pickup' | 'campus_delivery' | 'hostel_delivery'
  String _deliveryType = 'pickup';
  final _locationController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _scheduledFor;

  // Pack allocation (Section 11) — null until the student answers the
  // "Will you be using packs?" prompt; empty list means "No".
  List<PackAllocation>? _packs;

  static const _campusDeliveryFee = 200.0;
  static const _hostelDeliveryFee = 300.0;

  double get _deliveryFee => switch (_deliveryType) {
        'campus_delivery' => _campusDeliveryFee,
        'hostel_delivery' => _hostelDeliveryFee,
        _ => 0.0,
      };

  bool get _needsLocation =>
      _deliveryType == 'campus_delivery' ||
      _deliveryType == 'hostel_delivery';

  List<CartItem> _packableItems(List<CartItem> items) =>
      items.where((i) => i.product.requiresPack).toList();

  double get _packFee => (_packs?.length ?? 0) * widget.vendor.packPrice;

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(hours: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledFor =
          DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  /// Runs the transaction-PIN gate before any wallet funds move: prompts
  /// existing-without-a-PIN accounts to set one first, then always asks
  /// for the PIN itself. Returns null if the student backs out at either
  /// step — the caller should abort the order in that case.
  Future<String?> _collectPin() async {
    final hasPin =
        await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return null;
    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return null;
    }
    return showEnterPinSheet(context);
  }

  /// "Will you be using packs for this order?" — Yes opens the
  /// allocation flow, No records an empty pack list. Does nothing (keeps
  /// `_packs` null / undecided) if the student backs out of either.
  Future<void> _decidePacks(List<CartItem> packableItems) async {
    final wantsPacks = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Using packs?'),
        content: const Text(
          'Will you be using packs for this order? Some items in your '
          'cart need to be packaged into a container to be handed over.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
    if (wantsPacks == null || !mounted) return;

    if (!wantsPacks) {
      setState(() => _packs = []);
      return;
    }

    final result = await Navigator.of(context).push<List<PackAllocation>>(
      MaterialPageRoute(
        builder: (_) => PackAllocationScreen(
          vendor: widget.vendor,
          packableItems: packableItems,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _packs = result);
  }

  Future<void> _confirmOrder(List<CartItem> packableItems) async {
    if (_needsLocation) {
      if (!_formKey.currentState!.validate()) return;
    }
    if (packableItems.isNotEmpty && _packs == null) return;

    final pin = await _collectPin();
    if (pin == null || !mounted) return;

    final itemsByProductId = {
      for (final item in packableItems) item.product.id: item,
    };
    final packs = (_packs ?? [])
        .map((p) => p.toJson(itemsByProductId))
        .toList();

    final order = await ref.read(orderNotifierProvider.notifier).placeFoodOrder(
          vendor: widget.vendor,
          deliveryType: _deliveryType,
          pin: pin,
          packs: packs,
          packFee: _packFee,
          deliveryLocation: _needsLocation
              ? _locationController.text.trim()
              : null,
          scheduledFor: _scheduledFor,
        );

    if (!mounted) return;

    final notifierState = ref.read(orderNotifierProvider);

    if (order == null) {
      final error = notifierState.error ?? '';
      if (error == 'insufficient_balance') {
        // Handled inline — the button is already disabled, this shouldn't
        // normally be reached, but guard against a race.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Insufficient wallet balance. Please top up first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (error == 'invalid_pin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect PIN. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.isEmpty ? 'Order failed. Please try again.' : error),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Warn if the saving plan budget was exceeded (soft warning, not a block).
    if (notifierState.budgetWarning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Heads up: this order has put you over your saving plan budget for the current period.',
          ),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 5),
        ),
      );
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => OrderConfirmationScreen(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final orderState = ref.watch(orderNotifierProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);

    final packableItems = _packableItems(cart.items);
    final packDecisionPending = packableItems.isNotEmpty && _packs == null;

    final balance = balanceAsync.valueOrNull ?? 0.0;
    final total = cart.subtotal + _deliveryFee + _packFee;
    final hasSufficientBalance = balance >= total;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Checkout'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Order summary ────────────────────────────────────────
              Text('Order summary', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    ...cart.items.map(
                      (item) => Padding(
                        padding:
                            const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Text(
                              '${item.quantity}×',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                      style: theme.textTheme.bodyMedium),
                                  if (item.optionsSummary.isNotEmpty)
                                    Text(
                                      item.optionsSummary,
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                        color: theme.colorScheme.onSurface
                                            .withValues(alpha: 0.5),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              '₦${item.lineTotal.toStringAsFixed(0)}',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal',
                            style: theme.textTheme.bodySmall),
                        Text(
                          '₦${cart.subtotal.toStringAsFixed(0)}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Packing (Section 11) — only when the cart has any
              // pack-requiring items. Asked up front so the total below
              // is accurate by the time the student reaches Confirm.
              if (packableItems.isNotEmpty) ...[
                Text('Packing', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: packDecisionPending
                        ? AppColors.orange.withValues(alpha: 0.08)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: packDecisionPending
                        ? Border.all(color: AppColors.orange.withValues(alpha: 0.3))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        color: packDecisionPending
                            ? AppColors.orange
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          packDecisionPending
                              ? 'This order needs packs for some items.'
                              : (_packs!.isEmpty
                                  ? 'No packs — you\'re eating in / providing your own.'
                                  : '${_packs!.length} pack${_packs!.length == 1 ? '' : 's'} '
                                    '· +₦${_packFee.toStringAsFixed(0)}'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _decidePacks(packableItems),
                        child: Text(packDecisionPending ? 'Set up' : 'Change'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // ── Step 6: Fulfillment type ─────────────────────────────
              Text('How would you like to receive it?',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _FulfillmentChoice(
                          label: 'Pickup',
                          icon: Icons.storefront_outlined,
                          subtitle: 'Free',
                          selected: _deliveryType == 'pickup',
                          onTap: () =>
                              setState(() => _deliveryType = 'pickup'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _FulfillmentChoice(
                          label: 'Campus Delivery',
                          icon: Icons.directions_walk_outlined,
                          subtitle:
                              '+₦${_campusDeliveryFee.toStringAsFixed(0)}',
                          selected: _deliveryType == 'campus_delivery',
                          onTap: () => setState(
                              () => _deliveryType = 'campus_delivery'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _FulfillmentChoice(
                    label: 'Hostel Room Delivery',
                    icon: Icons.hotel_outlined,
                    subtitle:
                        '+₦${_hostelDeliveryFee.toStringAsFixed(0)}',
                    selected: _deliveryType == 'hostel_delivery',
                    onTap: () =>
                        setState(() => _deliveryType = 'hostel_delivery'),
                  ),
                ],
              ),

              // ── Step 7: Delivery location ────────────────────────────
              if (_needsLocation) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _deliveryType == 'hostel_delivery'
                      ? 'Hostel & room number'
                      : 'Delivery location',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _locationController,
                  hint: _deliveryType == 'hostel_delivery'
                      ? 'e.g. Elijah Hall, Room 204'
                      : 'e.g. Faculty of Science building entrance',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter a delivery location'
                      : null,
                ),
              ],

              // ── Step 7b: Schedule for later ──────────────────────────
              const SizedBox(height: AppSpacing.lg),
              Text('When?', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _ScheduleRow(
                scheduledFor: _scheduledFor,
                onPickSchedule: _pickSchedule,
                onClear: () => setState(() => _scheduledFor = null),
                theme: theme,
              ),

              const SizedBox(height: AppSpacing.xl),

              // ── Order total ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    _TotalRow(
                        label: 'Subtotal',
                        value: '₦${cart.subtotal.toStringAsFixed(0)}',
                        bold: false,
                        theme: theme),
                    if (_deliveryFee > 0)
                      _TotalRow(
                        label: 'Delivery fee',
                        value: '+₦${_deliveryFee.toStringAsFixed(0)}',
                        bold: false,
                        theme: theme,
                      ),
                    if (_packFee > 0)
                      _TotalRow(
                        label: 'Packs (${_packs!.length})',
                        value: '+₦${_packFee.toStringAsFixed(0)}',
                        bold: false,
                        theme: theme,
                      ),
                    const Divider(height: AppSpacing.md),
                    _TotalRow(
                      label: 'Total',
                      value: '₦${total.toStringAsFixed(0)}',
                      bold: true,
                      theme: theme,
                    ),
                    const Divider(height: AppSpacing.md),
                    // Wallet balance row
                    balanceAsync.when(
                      data: (b) => _TotalRow(
                        label: 'Wallet balance',
                        value: '₦${(b ?? 0).toStringAsFixed(0)}',
                        bold: false,
                        theme: theme,
                        valueColor: hasSufficientBalance
                            ? AppColors.emerald
                            : AppColors.error,
                      ),
                      loading: () => const SizedBox(
                        height: 20,
                        child: Center(
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              // Insufficient balance message
              if (!hasSufficientBalance && balanceAsync.hasValue) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.error, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            text: 'Insufficient balance. ',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: AppColors.error),
                            children: [
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () {
                                    // Navigate to the Wallet tab (index 2)
                                    // by popping back to the shell.
                                    Navigator.of(context).popUntil(
                                        (route) => route.isFirst);
                                  },
                                  child: Text(
                                    'Top up your wallet →',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600,
                                      decoration:
                                          TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.md,
          ),
          child: PrimaryButton(
            label: packDecisionPending
                ? 'Set up packs to continue'
                : 'Confirm Order  ₦${total.toStringAsFixed(0)}',
            icon: Icons.lock_outline,
            isLoading: orderState.isLoading,
            onPressed: (hasSufficientBalance && !packDecisionPending)
                ? () => _confirmOrder(packableItems)
                : null,
          ),
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.scheduledFor,
    required this.onPickSchedule,
    required this.onClear,
    required this.theme,
  });
  final DateTime? scheduledFor;
  final VoidCallback onPickSchedule;
  final VoidCallback onClear;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    if (scheduledFor == null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.schedule_outlined),
        label: const Text('Order ASAP (schedule for later)'),
        onPressed: onPickSchedule,
      );
    }
    final dt = scheduledFor!;
    final label =
        '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        const Icon(Icons.schedule, size: 18),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text('Scheduled for $label',
              style: theme.textTheme.bodyMedium),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClear,
          tooltip: 'Remove schedule',
        ),
      ],
    );
  }
}

class _FulfillmentChoice extends StatelessWidget {
  const _FulfillmentChoice({
    required this.label,
    required this.icon,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.dividerColor,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelMedium),
            Text(
              subtitle,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    required this.bold,
    required this.theme,
    this.valueColor,
  });
  final String label;
  final String value;
  final bool bold;
  final ThemeData theme;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? theme.textTheme.titleSmall
                : theme.textTheme.bodyMedium,
          ),
          Text(
            value,
            style: (bold
                    ? theme.textTheme.titleSmall
                    : theme.textTheme.labelMedium)
                ?.copyWith(
              color: valueColor ??
                  (bold ? theme.colorScheme.primary : null),
            ),
          ),
        ],
      ),
    );
  }
}
