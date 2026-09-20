import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/around_category.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/pin/pin_entry_sheet.dart';
import '../ordering/order_confirmation_screen.dart';
import '../ordering/order_repository.dart';

/// Around request flow — the student sets a pickup point, drop-off
/// point, and a text description of what needs fetching. The flow skips
/// the menu/cart entirely and calls [place_around_with_payment] which
/// atomically deducts the wallet and creates the order record.
///
/// [category] comes from the admin-configurable `around_categories`
/// table (post-testing fixes, Section 9) rather than a hardcoded enum.
class AroundScreen extends ConsumerStatefulWidget {
  const AroundScreen({super.key, required this.category});

  final AroundCategoryData category;

  @override
  ConsumerState<AroundScreen> createState() => _AroundScreenState();
}

class _AroundScreenState extends ConsumerState<AroundScreen> {
  final _formKey = GlobalKey<FormState>();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _pickupController.dispose();
    _dropoffController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _pickupLabel => switch (widget.category.key) {
        'laundry' => 'Pickup location (your hostel / room)',
        'hostel' => 'Pickup location',
        'peer_courier' => 'Pickup from',
        _ => 'Pickup location',
      };

  String get _dropoffLabel => switch (widget.category.key) {
        'laundry' => 'Laundry point / drop-off location',
        'hostel' => 'Drop-off location',
        'peer_courier' => 'Deliver to',
        _ => 'Drop-off location',
      };

  String get _descriptionLabel => switch (widget.category.key) {
        'laundry' => 'Notes for the rider (bag colour, count, etc.)',
        'vendor_fetch' => 'What to fetch — include shop name and item details',
        _ => 'Describe what needs to be carried / fetched',
      };

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

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;

    final pin = await _collectPin();
    if (pin == null || !mounted) return;

    final order = await ref
        .read(orderNotifierProvider.notifier)
        .placeAroundRequest(
          categoryKey: widget.category.key,
          fee: widget.category.flatFee,
          pickupLocation: _pickupController.text.trim(),
          dropoffLocation: _dropoffController.text.trim(),
          itemDescription: _descriptionController.text.trim(),
          pin: pin,
        );

    if (!mounted) return;
    final notifierState = ref.read(orderNotifierProvider);

    if (order == null) {
      final error = notifierState.error ?? '';
      if (error == 'insufficient_balance') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Insufficient wallet balance. Please top up your wallet first.',
            ),
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
            content: Text(error.isEmpty ? 'Request failed. Try again.' : error),
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
            'Heads up: this request has put you over your saving plan budget.',
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
    final orderState = ref.watch(orderNotifierProvider);
    final fee = widget.category.flatFee;

    return Scaffold(
      appBar: UniflexAppBar(title: widget.category.title),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      widget.category.icon,
                      color: theme.colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        widget.category.description,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Pickup
              Text(_pickupLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _pickupController,
                hint: 'e.g. Block B, Room 12, Elijah Hall',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter pickup location'
                    : null,
              ),

              const SizedBox(height: AppSpacing.md),

              // Dropoff
              Text(_dropoffLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _dropoffController,
                hint: 'e.g. Laundry Hub, Main Gate',
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter drop-off location'
                    : null,
              ),

              const SizedBox(height: AppSpacing.md),

              // Description
              Text(_descriptionLabel, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _descriptionController,
                hint: 'Be specific — size, colour, quantity, shop name…',
                maxLines: 3,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Please describe what needs to be done'
                    : null,
              ),

              const SizedBox(height: AppSpacing.xl),

              // Fee estimate
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Estimated fee',
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          '₦${fee.toStringAsFixed(0)}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Flat rate for this category, set by Admin.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              PrimaryButton(
                label: 'Confirm Request  ₦${fee.toStringAsFixed(0)}',
                icon: Icons.lock_outline,
                isLoading: orderState.isLoading,
                onPressed: _confirm,
              ),

              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
