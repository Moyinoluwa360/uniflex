import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_location.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cart/summary_row.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/navigation/app_bottom_nav_shell.dart';
import '../../shared/widgets/notice/app_inline_notice.dart';
import '../../shared/widgets/sheets/app_sheet.dart';
import '../gifts/gift_models.dart';
import '../gifts/gift_section.dart';
import 'cart_provider.dart';
import 'commitment_fee_screen.dart';
import 'checkout_draft.dart';
import 'order_repository.dart';

/// Round 8 checkout screen — multi-vendor aware, location-based fees.
///
/// Pickup is only offered when every vendor in the cart is Uniflex.
/// Delivery uses a named location from `delivery_locations` table;
/// the fee is calculated per vendor using pack brackets:
///   fee = location.price × ceil(packs / 3)  (0 packs = 1×).
///
/// **Pack 4A:** this screen only collects choices. The bottom button is
/// "Continue": it validates the form and opens the payment page
/// ([CommitmentFeeScreen]) with the cart and options held in memory. It
/// creates nothing in the database, does not clear the cart and does not
/// touch any order provider — the order is created (and the cart cleared)
/// only after the student pays on the next page.
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

  // Pack 6: "Send as a gift" (food delivery only).
  bool _giftOn = false;
  GiftRecipient? _giftRecipient;
  final _giftMessageController = TextEditingController();

  /// Guards against a second tap while the payment page is open/opening.
  bool _isContinuing = false;

  @override
  void dispose() {
    _locationDetailsController.dispose();
    _notesController.dispose();
    _giftMessageController.dispose();
    super.dispose();
  }

  Future<void> _pickSchedule() async {
    final now = DateTime.now();
    var next = DateTime(
        now.year, now.month, now.day, now.hour, now.minute >= 30 ? 30 : 0);
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

    final picked = await AppSheet.show<DateTime>(
      context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick a time', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text("Same-day pre-order — choose when you'd like it ready.",
                style: AppTypography.meta(ctx.colors)),
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
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() => _scheduledFor = picked);
  }

  /// Validates the form and opens the payment page. Creates nothing.
  Future<void> _continue() async {
    if (_isContinuing) return;
    if (!_formKey.currentState!.validate()) return;

    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return;

    if (!_isPickup && _selectedLocation == null) {
      _snack('Please select a delivery location.');
      return;
    }
    if (!_isPickup && _giftOn && _giftRecipient == null) {
      _snack('Find the student you are sending this to first.');
      return;
    }
    if (_isPickup && !cart.isUniflexOnly) {
      _snack('Pickup is only available for Uniflex orders.');
      return;
    }
    if (_isPickup &&
        _scheduledFor != null &&
        !_scheduledFor!.isAfter(DateTime.now())) {
      setState(() => _scheduledFor = null);
      _snack('That pickup time has passed. Pick a new time or order now.');
      return;
    }

    final draft = CheckoutDraft.fromCart(
      cart,
      isPickup: _isPickup,
      location: _isPickup ? null : _selectedLocation,
      locationDetails: _isPickup ? null : _locationDetailsController.text,
      note: _notesController.text,
      scheduledFor: _isPickup ? _scheduledFor : null,
      giftRecipient: (_giftOn && !_isPickup) ? _giftRecipient : null,
      giftMessage: _giftMessageController.text,
    );

    setState(() => _isContinuing = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CommitmentFeeScreen(draft: draft)),
      );
    } finally {
      if (mounted) setState(() => _isContinuing = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final cart = ref.watch(cartProvider);
    final balanceAsync = ref.watch(walletBalanceProvider);
    final locationsAsync = ref.watch(deliveryLocationsProvider);

    final isUniflexOnly = cart.isUniflexOnly;

    final vendorGroups = cart.groups.values.where((g) => !g.isEmpty).toList();

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
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int vi = 0; vi < vendorGroups.length; vi++) ...[
                      if (vi > 0) const Divider(height: AppSpacing.md),
                      Row(
                        children: [
                          Icon(AppIcons.vendor,
                              size: 16, color: c.textSecondary),
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
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: c.textSecondary,
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
                                            style: AppTypography.caption(c),
                                          ),
                                      ],
                                    ),
                                  ),
                                  MoneyText(
                                    item.lineTotal,
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      if (vendorGroups[vi].packFee > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${vendorGroups[vi].packCount} pack${vendorGroups[vi].packCount > 1 ? 's' : ''}',
                                style: AppTypography.meta(c),
                              ),
                              Text(
                                Money.plus(vendorGroups[vi].packFee),
                                style: AppTypography.tabular(
                                    AppTypography.meta(c)),
                              ),
                            ],
                          ),
                        ),
                    ],
                    const Divider(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal', style: theme.textTheme.bodySmall),
                        MoneyText(
                          cart.subtotal + cart.totalPackFee,
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
                        icon: AppIcons.vendor,
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
                      icon: AppIcons.delivery,
                      subtitle: _selectedLocation != null
                          ? '${Money.format(_selectedLocation!.price)}/bracket'
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
                Text('Delivery location', style: theme.textTheme.titleSmall),
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
                    style: AppTypography.meta(c).copyWith(color: c.dangerText),
                  ),
                  data: (locations) => DropdownButtonFormField<String>(
                    initialValue: _selectedLocation?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Where should we deliver?',
                    ),
                    items: [
                      for (final loc in locations)
                        DropdownMenuItem(
                          value: loc.id,
                          child: Text(
                            '${loc.name}  (${Money.format(loc.price)})',
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

              // ── Send as a gift (food delivery only) ─────────────────
              if (!_isPickup) ...[
                const SizedBox(height: AppSpacing.md),
                GiftSection(
                  enabled: _giftOn,
                  recipient: _giftRecipient,
                  messageController: _giftMessageController,
                  onEnabledChanged: (v) => setState(() {
                    _giftOn = v;
                    if (!v) _giftRecipient = null;
                  }),
                  onRecipientChanged: (r) => setState(() => _giftRecipient = r),
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
              AppCard(
                child: Column(
                  children: [
                    SummaryRow(
                      // No pack wording when every vendor is fixed-menu;
                      // pack-based carts read exactly as before.
                      label: vendorGroups.every((g) => g.vendor.isFixedMenu)
                          ? 'Food'
                          : 'Food + packs',
                      value: Money.format(cart.subtotal + cart.totalPackFee),
                      bold: false,
                    ),
                    if (!_isPickup && _selectedLocation != null) ...[
                      for (final g in vendorGroups)
                        SummaryRow(
                          label: 'Delivery (${g.vendor.name})',
                          value: Money.plus(
                              vendorDeliveryFee(locationPrice, g.packCount)),
                          bold: false,
                        ),
                    ],
                    const Divider(height: AppSpacing.md),
                    if (_isPickup)
                      SummaryRow(
                        label: 'Total',
                        value: Money.format(cart.subtotal + cart.totalPackFee),
                        bold: true,
                      )
                    else ...[
                      SummaryRow(
                        label: 'Delivery fees',
                        value: Money.format(totalDeliveryFee),
                        bold: true,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'A small service charge is added on the next page. Food is paid after the rider confirms the price.',
                        style: AppTypography.caption(c),
                      ),
                    ],
                    const Divider(height: AppSpacing.md),
                    if (_isPickup)
                      balanceAsync.when(
                        data: (b) => SummaryRow(
                          label: 'Wallet balance',
                          value: Money.format(b ?? 0),
                          bold: false,
                          valueColor:
                              hasSufficientBalance ? c.brandText : c.dangerText,
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
                AppInlineNotice.custom(
                  isError: true,
                  icon: AppIcons.error,
                  child: Text.rich(
                    TextSpan(
                      text: 'Insufficient balance. ',
                      style:
                          AppTypography.meta(c).copyWith(color: c.dangerText),
                      children: [
                        WidgetSpan(
                          child: GestureDetector(
                            onTap: () {
                              ref.read(shellTabRequestProvider.notifier).state =
                                  _studentWalletTabIndex;
                              Navigator.of(context)
                                  .popUntil((route) => route.isFirst);
                            },
                            child: Text(
                              'Top up your wallet →',
                              style: AppTypography.meta(c).copyWith(
                                color: c.dangerText,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
        child: AppButton(
          label: 'Continue',
          icon: AppIcons.forward,
          isLoading: _isContinuing,
          onPressed: _isContinuing ? null : _continue,
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
      return AppButton(
        icon: AppIcons.clock,
        label: 'Order ASAP (schedule for later)',
        variant: AppButtonVariant.secondary,
        onPressed: onPickSchedule,
      );
    }
    final dt = scheduledFor!;
    final label =
        'Today at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Row(
      children: [
        Icon(AppIcons.clock, size: 18, color: context.colors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child:
              Text('Scheduled for $label', style: theme.textTheme.bodyMedium),
        ),
        IconButton(
          icon: Icon(AppIcons.close,
              size: 18, color: context.colors.textTertiary),
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
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? c.brand : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected ? c.brandText : c.textTertiary,
            ),
            const SizedBox(height: 4),
            Text(label, style: theme.textTheme.labelMedium),
            Text(
              subtitle,
              style: AppTypography.caption(c).copyWith(
                color: selected ? c.brandText : c.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
