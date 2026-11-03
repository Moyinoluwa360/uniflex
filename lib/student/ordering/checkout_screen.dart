import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_location.dart';
import '../../shared/models/order.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/navigation/app_bottom_nav_shell.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../../shared/widgets/sheets/acknowledgment_sheet.dart';
import 'cart_provider.dart';
import 'commitment_fee_screen.dart';
import 'order_confirmation_screen.dart';
import 'order_repository.dart';

/// Round 8 checkout screen — multi-vendor aware, location-based fees.
///
/// Pickup is only offered when every vendor in the cart is Uniflex.
/// Delivery uses a named location from `delivery_locations` table;
/// the fee is calculated per vendor using pack brackets:
///   fee = location.price × ceil(packs / 3)  (0 packs = 1×).
///
/// Pickup for Uniflex orders uses the existing [placeFoodOrder] RPC
/// (full payment upfront with PIN).
const _studentWalletTabIndex = 2;

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  bool _isPickup = false;
  DeliveryLocation? _selectedLocation;
  final _locationDetailsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DateTime? _scheduledFor;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _locationDetailsController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    var next = DateTime(now.year, now.month, now.day,
        now.hour, now.minute >= 30 ? 30 : 0);
    while (!next.isAfter(now.add(const Duration(minutes: 29)))) {
      next = next.add(const Duration(minutes: 30));
    }

    final slots = <DateTime>[];
    final endOfDay = DateTime(now.year, now.month, now.day, 22, 0);
    while (!next.isAfter(endOfDay)) {
      slots.add(next);
      next = next.add(const Duration(minutes: 30));
    }

    if (slots.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No more time slots available today.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pick a time', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text("Same-day pre-order — choose when you'd like it ready.",
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    )),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: slots.map((slot) {
                    final label =
                        '${slot.hour.toString().padLeft(2, '0')}:${slot.minute.toString().padLeft(2, '0')}';
                    return ActionChip(
                      label: Text(label),
                      onPressed: () => Navigator.pop(ctx, slot),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() => _scheduledFor = picked);
  }

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

  Future<void> _confirmOrder() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;

    // Delivery requires a selected location.
    if (!_isPickup && _selectedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a delivery location.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Acknowledgment for delivery orders.
    if (!_isPickup) {
      final ok = await showAcknowledgmentSheet(
        context,
        message:
            "You're paying the delivery fee only. Your food is paid for "
            "after the rider confirms your order. We'll notify you when "
            "it's time to pay.",
      );
      if (!ok || !mounted) return;
    }

    setState(() => _isSubmitting = true);

    try {
      await _doConfirmOrder();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _doConfirmOrder() async {
    final cart = ref.read(cartProvider);
    final notes = _notesController.text.trim();

    if (_isPickup) {
      // Pickup is only available for Uniflex-only carts (enforced by UI).
      final vendor = cart.vendor;
      if (vendor == null) return;

      final pin = await _collectPin();
      if (pin == null || !mounted) return;

      // Build pack data from cart's group.
      final group = cart.groups[vendor.id];
      final packs = (group?.packContents ?? [])
          .map((contents) => {
                'items': contents.entries
                    .where((e) => e.value > 0)
                    .map((e) {
                      final product = group!.items.firstWhere(
                        (i) => i.product.id == e.key,
                        orElse: () => group.items.first,
                      );
                      return {
                        'product_id': e.key,
                        'product_name': product.product.name,
                        'quantity': e.value,
                      };
                    })
                    .toList(),
              })
          .toList();

      final order = await ref.read(orderNotifierProvider.notifier).placeFoodOrder(
            vendor: vendor,
            deliveryType: 'pickup',
            pin: pin,
            packs: packs,
            packFee: group?.packFee ?? 0,
            deliveryLocation: null,
            scheduledFor: _scheduledFor,
            notes: notes.isEmpty ? null : notes,
          );

      if (!mounted) return;
      _handleSingleOrderResult(order);
    } else {
      // Delivery: multi-vendor flow via delivery_groups.
      final loc = _selectedLocation!;
      final details = _locationDetailsController.text.trim();

      final result = await ref
          .read(orderNotifierProvider.notifier)
          .placeMultiVendorOrder(
            deliveryType: 'delivery',
            deliveryLocation: loc.name,
            studentNote: notes.isEmpty ? null : notes,
            scheduledFor: _scheduledFor,
            deliveryLocationId: loc.id,
            locationDetails: details.isEmpty ? null : details,
          );

      if (!mounted) return;

      if (result == null) {
        final error = ref.read(orderNotifierProvider).error ?? '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.isEmpty ? 'Order failed. Please try again.' : error),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      // Navigate to commitment fee screen (delivery fee = commitment fee).
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CommitmentFeeScreen(
            groupId: result.groupId,
            commitmentFeeTotal: result.commitmentFeeTotal,
            vendorCount: result.vendorCount,
          ),
        ),
      );
    }
  }

  void _handleSingleOrderResult(Order? order) {
    final notifierState = ref.read(orderNotifierProvider);

    if (order == null) {
      final error = notifierState.error ?? '';
      if (error == 'insufficient_balance') {
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
    final locationsAsync = ref.watch(deliveryLocationsProvider);

    final isUniflexOnly = cart.isUniflexOnly;

    final vendorGroups = cart.groups.values
        .where((g) => !g.isEmpty)
        .toList();

    // Calculate delivery fee per vendor using pack brackets.
    final locationPrice = _selectedLocation?.price ?? 0;
    double totalDeliveryFee = 0;
    if (!_isPickup && _selectedLocation != null) {
      for (final g in vendorGroups) {
        totalDeliveryFee += vendorDeliveryFee(locationPrice, g.packCount);
      }
    }

    final balance = balanceAsync.valueOrNull ?? 0.0;

    // For pickup (Uniflex, full payment): need sufficient balance.
    // For delivery (commitment fee only): balance check is on the next screen.
    final hasSufficientBalance =
        _isPickup ? balance >= (cart.subtotal + cart.totalPackFee) : true;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Checkout'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Order summary (grouped by vendor) ──────────────────
              Text('Order summary', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int vi = 0; vi < vendorGroups.length; vi++) ...[
                      if (vi > 0) const Divider(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(Icons.storefront,
                              size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            vendorGroups[vi].vendor.name,
                            style: theme.textTheme.labelLarge,
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ...vendorGroups[vi].items.map(
                        (item) => Padding(
                          padding:
                              const EdgeInsets.only(bottom: AppSpacing.xs),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(item.product.name,
                                        style: theme.textTheme.bodyMedium),
                                    if (item.optionsSummary.isNotEmpty)
                                      Text(
                                        item.optionsSummary,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurface
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
                      if (vendorGroups[vi].packFee > 0)
                        Padding(
                          padding:
                              const EdgeInsets.only(top: AppSpacing.xs),
                          child: Row(
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${vendorGroups[vi].packCount} pack${vendorGroups[vi].packCount > 1 ? 's' : ''}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: AppColors.emerald,
                                ),
                              ),
                              Text(
                                '+₦${vendorGroups[vi].packFee.toStringAsFixed(0)}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppColors.emerald,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Divider(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal',
                            style: theme.textTheme.bodySmall),
                        Text(
                          '₦${(cart.subtotal + cart.totalPackFee).toStringAsFixed(0)}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Fulfillment type ─────────────────────────────────────
              Text('How would you like to receive it?',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  if (isUniflexOnly) ...[
                    Expanded(
                      child: _FulfillmentChoice(
                        label: 'Pickup',
                        icon: Icons.storefront_outlined,
                        subtitle: 'Free',
                        selected: _isPickup,
                        onTap: () => setState(() => _isPickup = true),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Expanded(
                    child: _FulfillmentChoice(
                      label: 'Delivery',
                      icon: Icons.delivery_dining_outlined,
                      subtitle: _selectedLocation != null
                          ? '₦${_selectedLocation!.price.toStringAsFixed(0)}/bracket'
                          : 'Select location',
                      selected: !_isPickup,
                      onTap: () => setState(() => _isPickup = false),
                    ),
                  ),
                ],
              ),

              // ── Delivery location dropdown ──────────────────────────
              if (!_isPickup) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('Delivery location',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                locationsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  error: (_, __) => Text(
                    'Could not load locations.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.error),
                  ),
                  data: (locations) => DropdownButtonFormField<String>(
                    value: _selectedLocation?.id,
                    decoration: const InputDecoration(
                      labelText: 'Where should we deliver?',
                    ),
                    items: [
                      for (final loc in locations)
                        DropdownMenuItem(
                          value: loc.id,
                          child: Text(
                            '${loc.name}  (₦${loc.price.toStringAsFixed(0)})',
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      final locations =
                          ref.read(deliveryLocationsProvider).valueOrNull ?? [];
                      final loc = locations.firstWhere((l) => l.id == id);
                      setState(() => _selectedLocation = loc);
                    },
                    validator: (v) =>
                        v == null ? 'Select a delivery location' : null,
                  ),
                ),

                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _locationDetailsController,
                  label: 'Location details',
                  hint: 'e.g. Room 204, Elijah Hall',
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Describe exactly where to deliver'
                      : null,
                ),
              ],

              // ── Schedule (pickup only) ──────────────────────────────
              if (_isPickup) ...[
                const SizedBox(height: AppSpacing.lg),
                Text('When?', style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                _ScheduleRow(
                  scheduledFor: _scheduledFor,
                  onPickSchedule: _pickSchedule,
                  onClear: () => setState(() => _scheduledFor = null),
                  theme: theme,
                ),
              ],

              // ── Notes ────────────────────────────────────────────────
              const SizedBox(height: AppSpacing.lg),
              Text('Note for the rider (optional)',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _notesController,
                hint: 'e.g. Extra napkins please, or call when you arrive',
                maxLines: 2,
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
                      label: 'Food + packs',
                      value:
                          '₦${(cart.subtotal + cart.totalPackFee).toStringAsFixed(0)}',
                      bold: false,
                      theme: theme,
                    ),
                    if (!_isPickup && _selectedLocation != null) ...[
                      for (final g in vendorGroups)
                        _TotalRow(
                          label: 'Delivery (${g.vendor.name})',
                          value:
                              '+₦${vendorDeliveryFee(locationPrice, g.packCount).toStringAsFixed(0)}',
                          bold: false,
                          theme: theme,
                        ),
                    ],
                    const Divider(height: AppSpacing.md),
                    if (_isPickup)
                      _TotalRow(
                        label: 'Total',
                        value:
                            '₦${(cart.subtotal + cart.totalPackFee).toStringAsFixed(0)}',
                        bold: true,
                        theme: theme,
                      )
                    else ...[
                      _TotalRow(
                        label: 'Commitment fee (delivery)',
                        value:
                            '₦${totalDeliveryFee.toStringAsFixed(0)}',
                        bold: true,
                        theme: theme,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Food cost is paid after items are confirmed.',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                    const Divider(height: AppSpacing.md),
                    if (_isPickup)
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),

              // Insufficient balance message (pickup only).
              if (_isPickup &&
                  !hasSufficientBalance &&
                  balanceAsync.hasValue) ...[
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
                                    ref
                                        .read(shellTabRequestProvider.notifier)
                                        .state = _studentWalletTabIndex;
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

      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenGutter,
          AppSpacing.sm,
          AppSpacing.screenGutter,
          MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              AppSpacing.md,
        ),
        child: PrimaryButton(
          label: _isPickup
              ? 'Confirm Order  ₦${(cart.subtotal + cart.totalPackFee).toStringAsFixed(0)}'
              : 'Place Order (₦${totalDeliveryFee.toStringAsFixed(0)} delivery fee)',
          icon: _isPickup ? Icons.lock_outline : Icons.shopping_cart_checkout,
          isLoading: orderState.isLoading || _isSubmitting,
          onPressed: (hasSufficientBalance && !_isSubmitting)
              ? _confirmOrder
              : null,
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
    if (scheduledFor == null) {
      return OutlinedButton.icon(
        icon: const Icon(Icons.schedule_outlined),
        label: const Text('Order ASAP (schedule for later)'),
        onPressed: onPickSchedule,
      );
    }
    final dt = scheduledFor!;
    final label =
        'Today at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
