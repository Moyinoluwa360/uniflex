import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/settings/service_charge_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../services/admin_providers.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Validates the service-charge field: a whole number, 0 or more.
/// Returns an error message, or null when the value is acceptable.
String? validateServiceCharge(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return 'Enter an amount (0 or more).';
  final n = int.tryParse(text);
  if (n == null) return 'Use a whole number, like 30.';
  if (n < 0) return 'The amount cannot be negative.';
  if (n > 100000) return 'That amount is too large.';
  return null;
}

/// Manage → Service charge. The flat fee added once to every food delivery
/// and errand when the student pays (not to pickup orders). Changing it
/// only affects orders placed afterwards.
class ServiceChargeScreen extends ConsumerStatefulWidget {
  const ServiceChargeScreen({super.key});

  @override
  ConsumerState<ServiceChargeScreen> createState() =>
      _ServiceChargeScreenState();
}

class _ServiceChargeScreenState extends ConsumerState<ServiceChargeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final amount = int.parse(_controller.text.trim());

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(adminServiceProvider).setServiceCharge(amount);
      ref.invalidate(serviceChargeProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Service charge is now ₦$amount.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = AppErrorMapper.map(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = ref.watch(serviceChargeProvider);

    // Fill the field once with the value currently stored.
    final loaded = current.valueOrNull;
    if (!_seeded && loaded != null) {
      _seeded = true;
      _controller.text = loaded.toStringAsFixed(0);
    }

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Service charge'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A flat fee added once to every food delivery and errand when '
                'the student pays. It is not charged on pickup orders and '
                'riders never see it. Changing it affects only new orders.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Amount (₦)', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                controller: _controller,
                enabled: !_saving,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  prefixText: '₦ ',
                  border: const OutlineInputBorder(),
                  helperText: current.hasError
                      ? 'Could not load the current value.'
                      : null,
                ),
                validator: validateServiceCharge,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Save',
                icon: Icons.check,
                isLoading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
