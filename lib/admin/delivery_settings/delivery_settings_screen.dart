import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../student/ordering/order_repository.dart';

/// Admin screen for editing the delivery fee settings stored in the
/// `delivery_settings` table. Values here drive commitment fees in the
/// multi-vendor checkout flow (Round 7).
class DeliverySettingsScreen extends ConsumerStatefulWidget {
  const DeliverySettingsScreen({super.key});

  @override
  ConsumerState<DeliverySettingsScreen> createState() =>
      _DeliverySettingsScreenState();
}

class _DeliverySettingsScreenState
    extends ConsumerState<DeliverySettingsScreen> {
  final _campusController = TextEditingController();
  final _hostelController = TextEditingController();
  bool _isSaving = false;
  bool _loaded = false;

  @override
  void dispose() {
    _campusController.dispose();
    _hostelController.dispose();
    super.dispose();
  }

  void _populateFromSettings(Map<String, String> settings) {
    if (_loaded) return;
    _loaded = true;
    _campusController.text = settings['campus_delivery_fee'] ?? '200';
    _hostelController.text = settings['hostel_delivery_fee'] ?? '300';
  }

  Future<void> _save() async {
    final campus = double.tryParse(_campusController.text.trim());
    final hostel = double.tryParse(_hostelController.text.trim());
    if (campus == null || hostel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter valid numbers for both fees.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('update_delivery_setting', params: {
        'p_key': 'campus_delivery_fee',
        'p_value': campus.toStringAsFixed(0),
      });
      await client.rpc('update_delivery_setting', params: {
        'p_key': 'hostel_delivery_fee',
        'p_value': hostel.toStringAsFixed(0),
      });

      ref.invalidate(deliverySettingsProvider);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery fees updated.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(deliverySettingsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Delivery Fees'),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (settings) {
          _populateFromSettings(settings);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    border: Border.all(
                        color: AppColors.info.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    'These fees are charged per vendor in a delivery order. '
                    'They serve as the commitment fee that dispatches a rider.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.info),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Campus Delivery Fee (per vendor)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _campusController,
                  hint: '200',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.payments_outlined,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Hostel Room Delivery Fee (per vendor)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(
                  controller: _hostelController,
                  hint: '300',
                  keyboardType: TextInputType.number,
                  prefixIcon: Icons.payments_outlined,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Save',
                  icon: Icons.save_outlined,
                  isLoading: _isSaving,
                  onPressed: _isSaving ? null : _save,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
