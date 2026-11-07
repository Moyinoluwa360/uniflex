import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_location.dart';
import '../../shared/models/errand_category.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/models/order.dart';
import '../../shared/services/settings/service_charge_provider.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import '../../shared/utils/uuid_v4.dart';
import '../../shared/widgets/payment/run_payment_flow.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../ordering/order_payment_repository.dart';
import '../ordering/order_repository.dart';
import 'errand_category_providers.dart';
import 'errand_confirmation_screen.dart';

/// Full-screen form for creating an errand request.
///
/// Category and description are required; all other fields are optional.
/// Tapping "Pay" runs the shared payment step (note → PIN) and then ONE
/// server call that verifies the PIN, debits the errand fee + service
/// charge and creates the errand. No unpaid errand row ever exists.
class CreateErrandScreen extends ConsumerStatefulWidget {
  const CreateErrandScreen({super.key});

  @override
  ConsumerState<CreateErrandScreen> createState() => _CreateErrandScreenState();
}

class _CreateErrandScreenState extends ConsumerState<CreateErrandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _pickupController = TextEditingController();
  final _locationDetailsController = TextEditingController();

  ErrandCategoryData? _selectedCategory;
  DeliveryLocation? _selectedLocation;
  bool _isSubmitting = false;
  bool _inFlight = false;
  String? _error;

  /// One key per form; re-sent on retry so a repeat never double-charges.
  final String _idempotencyKey = newUuidV4();

  @override
  void dispose() {
    _descriptionController.dispose();
    _pickupController.dispose();
    _locationDetailsController.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _selectedCategory != null &&
      _descriptionController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    if (_inFlight) return;
    if (!_canSubmit) return;
    if (!_formKey.currentState!.validate()) return;
    _inFlight = true;
    setState(() => _error = null);

    final category = _selectedCategory!;
    final loc = _selectedLocation;
    final details = _locationDetailsController.text.trim();
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(orderPaymentRepositoryProvider);
    final serviceCharge = ref.read(serviceChargeProvider).valueOrNull;
    final total = category.flatFee + (serviceCharge ?? 0);
    PaidOrderResult? paid;

    try {
      final result = await runPaymentFlow(
        context: context,
        ref: ref,
        acknowledgeMessage: "You're paying the errand fee and service charge. "
            'Your rider will call you to sort out the details.',
        pinTitle: 'Confirm errand payment',
        pinSubtitle:
            'Enter your 4-digit PIN to pay ₦${total.toStringAsFixed(0)}.',
        setSubmitting: (v) {
          if (mounted) setState(() => _isSubmitting = v);
        },
        onError: (message) {
          if (mounted) setState(() => _error = message);
        },
        onConfirm: (pin) async {
          paid = await repo.payErrand(
            idempotencyKey: _idempotencyKey,
            pin: pin,
            categoryKey: category.key,
            pickupLocation: _pickupController.text.trim(),
            dropoffLocation: '',
            itemDescription: _descriptionController.text.trim(),
            deliveryLocationId: loc?.id,
            locationDetails: details.isEmpty ? null : details,
          );
        },
      );
      if (result != PaymentFlowResult.success || paid == null) return;

      container.invalidate(walletBalanceProvider);
      container.invalidate(walletInfoProvider);
      container.invalidate(walletTransactionsProvider);
      container.invalidate(studentOrdersProvider);

      if (!mounted) return;
      final order = Order(
        id: paid!.orderId,
        studentId: '',
        source: 'uniflex',
        type: 'errand',
        status: OrderStatus.placed,
        deliveryType: 'delivery',
        totalAmount: category.flatFee,
        estimatedTime: '15–25 min',
        createdAt: DateTime.now(),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ErrandConfirmationScreen(order: order),
        ),
      );
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(activeErrandCategoriesProvider);
    final serviceAsync = ref.watch(serviceChargeProvider);
    final fee = _selectedCategory?.flatFee;
    final serviceCharge = serviceAsync.valueOrNull;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Create errand'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          onChanged: () => setState(() {}),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Category * ──────────────────────────────────────────────
              Text('Category *', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              categoriesAsync.when(
                loading: () => const SizedBox(
                  height: 56,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (_, __) => Text(
                  'Could not load categories. Pull down to retry.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
                data: (categories) => DropdownButtonFormField<String>(
                  initialValue: _selectedCategory?.id,
                  hint: const Text('Select a category'),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(
                            '${c.title}  ·  ₦${c.flatFee.toStringAsFixed(0)}'),
                      ),
                  ],
                  validator: (v) =>
                      v == null ? 'Please select a category' : null,
                  onChanged: (id) {
                    if (id == null) return;
                    final cat = categories.firstWhere((c) => c.id == id);
                    setState(() => _selectedCategory = cat);
                  },
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── What do you need done? * ─────────────────────────────────
              Text('What do you need done? *',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _descriptionController,
                hint: 'Be specific — size, colour, quantity, shop name…',
                maxLines: 4,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please describe what needs to be done'
                    : null,
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Pickup point (optional) ──────────────────────────────────
              Text('Pickup point (optional)',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _pickupController,
                hint: 'e.g. Block B, Room 12, Elijah Hall',
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Drop-off location (optional) ─────────────────────────────
              Text('Drop-off location (optional)',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Consumer(
                builder: (ctx, cref, _) {
                  final locsAsync = cref.watch(deliveryLocationsProvider);
                  return locsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (locations) => DropdownButtonFormField<String>(
                      initialValue: _selectedLocation?.id,
                      hint: const Text('Select area (optional)'),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.md,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '__none__',
                          child: Text('Not specified'),
                        ),
                        for (final loc in locations)
                          DropdownMenuItem(
                            value: loc.id,
                            child: Text(loc.name),
                          ),
                      ],
                      onChanged: (id) {
                        if (id == null || id == '__none__') {
                          setState(() => _selectedLocation = null);
                          return;
                        }
                        final loc = locations.firstWhere((l) => l.id == id);
                        setState(() => _selectedLocation = loc);
                      },
                    ),
                  );
                },
              ),
              if (_selectedLocation != null) ...[
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _locationDetailsController,
                  hint: 'e.g. Room 204',
                  label: 'Location details (optional)',
                ),
              ],

              const SizedBox(height: AppSpacing.xl),

              // ── Fee summary (shown only after category chosen) ───────────
              if (fee != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Errand fee', style: theme.textTheme.bodyMedium),
                          Text('₦${fee.toStringAsFixed(0)}',
                              style: theme.textTheme.bodyMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Service charge',
                              style: theme.textTheme.bodyMedium),
                          Text(
                            serviceCharge == null
                                ? '—'
                                : '₦${serviceCharge.toStringAsFixed(0)}',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                      const Divider(height: AppSpacing.lg),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total', style: theme.textTheme.titleSmall),
                          Text(
                            serviceCharge == null
                                ? '—'
                                : '₦${(fee + serviceCharge).toStringAsFixed(0)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.error),
                  ),
                ),

              // ── Pay button ───────────────────────────────────────────────
              PrimaryButton(
                label: (fee != null && serviceCharge != null)
                    ? 'Pay  ₦${(fee + serviceCharge).toStringAsFixed(0)}'
                    : 'Pay',
                icon: Icons.lock_outline,
                isLoading: _isSubmitting,
                onPressed: (_canSubmit && !_isSubmitting) ? _submit : null,
              ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
