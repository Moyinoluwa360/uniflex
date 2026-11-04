import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_location.dart';
import '../../shared/models/errand_category.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../../shared/widgets/sheets/acknowledgment_sheet.dart';
import '../ordering/order_repository.dart';
import 'errand_category_providers.dart';
import 'errand_confirmation_screen.dart';

/// Full-screen form for creating an errand request.
///
/// Category and description are required; all other fields are optional.
/// Tapping "Pay errand fee" places the order and navigates to
/// [CommitmentFeeScreen] for the PIN-gated payment.
class CreateErrandScreen extends ConsumerStatefulWidget {
  const CreateErrandScreen({super.key});

  @override
  ConsumerState<CreateErrandScreen> createState() =>
      _CreateErrandScreenState();
}

class _CreateErrandScreenState extends ConsumerState<CreateErrandScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _pickupController = TextEditingController();
  final _locationDetailsController = TextEditingController();

  ErrandCategoryData? _selectedCategory;
  DeliveryLocation? _selectedLocation;
  bool _isSubmitting = false;

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
    if (_isSubmitting) return;
    if (!_canSubmit) return;
    if (!_formKey.currentState!.validate()) return;

    final category = _selectedCategory!;

    final ok = await showAcknowledgmentSheet(
      context,
      message:
          "You're paying the errand fee (₦${category.flatFee.toStringAsFixed(0)}). "
          'Your rider will call you to sort out the details.',
    );
    if (!ok || !mounted) return;

    // Check / set PIN before collecting it.
    final hasPin =
        await ref.read(profileServiceProvider).hasTransactionPin();
    if (!mounted) return;

    if (!hasPin) {
      final didSet = await showSetPinSheet(context, ref);
      if (!mounted || !didSet) return;
    }

    final pin = await showEnterPinSheet(
      context,
      title: 'Confirm errand fee',
    );
    if (pin == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await _doSubmit(pin);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _doSubmit(String pin) async {
    final category = _selectedCategory!;
    final loc = _selectedLocation;
    final details = _locationDetailsController.text.trim();

    final order = await ref
        .read(orderNotifierProvider.notifier)
        .placeErrandRequest(
          categoryKey: category.key,
          fee: category.flatFee,
          pickupLocation: _pickupController.text.trim(),
          dropoffLocation: '',
          itemDescription: _descriptionController.text.trim(),
          pin: pin,
          deliveryLocationId: loc?.id,
          locationDetails: details.isEmpty ? null : details,
        );

    if (!mounted) return;

    if (order == null) {
      final err = ref.read(orderNotifierProvider).error ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err.isEmpty ? 'Request failed. Try again.' : err),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ErrandConfirmationScreen(order: order),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(activeErrandCategoriesProvider);
    final orderState = ref.watch(orderNotifierProvider);
    final fee = _selectedCategory?.flatFee;

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
                  value: _selectedCategory?.id,
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
                        child: Text('${c.title}  ·  ₦${c.flatFee.toStringAsFixed(0)}'),
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
                      value: _selectedLocation?.id,
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
                  padding:
                      const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Errand fee',
                          style: theme.textTheme.bodyMedium),
                      Text(
                        '₦${fee.toStringAsFixed(0)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Pay button ───────────────────────────────────────────────
              PrimaryButton(
                label: fee != null
                    ? 'Pay errand fee  ₦${fee.toStringAsFixed(0)}'
                    : 'Pay errand fee',
                icon: Icons.lock_outline,
                isLoading: orderState.isLoading || _isSubmitting,
                onPressed: _canSubmit && !_isSubmitting ? _submit : null,
              ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
