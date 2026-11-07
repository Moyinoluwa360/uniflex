import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/settings/support_whatsapp_provider.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/utils/phone_format.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../services/admin_providers.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Validates the WhatsApp field. Empty is allowed (it clears the number and
/// hides the WhatsApp option from students); anything else must be a
/// Nigerian number written as 0803… or +234803….
String? validateWhatsappNumber(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return null;
  if (normalizeNigerianPhone(text) == null) {
    return 'Enter a valid number, like 0803 123 4567 or +234 803 123 4567.';
  }
  return null;
}

/// Manage → Support settings. One WhatsApp number for students to message.
class SupportSettingsScreen extends ConsumerStatefulWidget {
  const SupportSettingsScreen({super.key});

  @override
  ConsumerState<SupportSettingsScreen> createState() =>
      _SupportSettingsScreenState();
}

class _SupportSettingsScreenState extends ConsumerState<SupportSettingsScreen> {
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final stored = await ref
          .read(adminServiceProvider)
          .setSupportWhatsapp(_controller.text.trim());
      ref.invalidate(supportWhatsappProvider);
      if (!mounted) return;
      if (stored != null) _controller.text = '+$stored';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(stored == null
              ? 'WhatsApp number removed. Students will only see live chat.'
              : 'WhatsApp number saved.'),
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
    final current = ref.watch(supportWhatsappProvider);

    final loaded = current.valueOrNull;
    if (!_seeded && current.hasValue) {
      _seeded = true;
      _controller.text = loaded == null ? '' : '+$loaded';
    }

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Support settings'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Students can message support on WhatsApp from Help & Support. '
                'Leave this empty to hide WhatsApp and show live chat only.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('WhatsApp number', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const ValueKey('whatsapp-field'),
                controller: _controller,
                enabled: !_saving,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: '0803 123 4567',
                  helperText: current.hasError
                      ? 'Could not load the current number.'
                      : 'Write it as 0803… or +234803… — we save it in the '
                          'international form.',
                ),
                validator: validateWhatsappNumber,
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
