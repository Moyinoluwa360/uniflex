import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Shows a bottom sheet asking the student to enter their 4-digit
/// transaction PIN. Returns the entered PIN, or `null` if dismissed.
/// The caller is responsible for verifying it (via
/// `ProfileService.hasTransactionPin` / the order-placement RPC's own
/// PIN check) — this sheet only collects the digits.
Future<String?> showEnterPinSheet(
  BuildContext context, {
  String title = 'Enter your transaction PIN',
  String subtitle = 'Confirm this order by entering your 4-digit PIN.',
}) {
  final controller = TextEditingController();
  String? error;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final theme = Theme.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.screenGutter,
            right: AppSpacing.screenGutter,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline, color: AppColors.emerald),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                style: theme.textTheme.headlineMedium?.copyWith(
                  letterSpacing: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: '• • • •',
                  counterText: '',
                  errorText: error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (controller.text.trim().length != 4) {
                      setState(() => error = 'Enter all 4 digits');
                      return;
                    }
                    Navigator.of(ctx).pop(controller.text.trim());
                  },
                  child: const Text('Confirm'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Shows a bottom sheet that lets the student set (or replace) their
/// 4-digit transaction PIN, calling `set_transaction_pin` on submit.
/// Returns `true` once a PIN has been saved, `false` if dismissed.
Future<bool> showSetPinSheet(BuildContext context, WidgetRef ref) async {
  final pinController = TextEditingController();
  final confirmController = TextEditingController();
  String? error;
  bool isSaving = false;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final theme = Theme.of(ctx);

        Future<void> submit() async {
          final pin = pinController.text.trim();
          final confirm = confirmController.text.trim();
          if (pin.length != 4) {
            setState(() => error = 'PIN must be exactly 4 digits');
            return;
          }
          if (pin != confirm) {
            setState(() => error = 'PINs do not match');
            return;
          }
          setState(() {
            isSaving = true;
            error = null;
          });
          try {
            await ref.read(profileServiceProvider).setTransactionPin(pin);
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } catch (e) {
            setState(() {
              isSaving = false;
              error = 'Could not save PIN. Try again.';
            });
          }
        }

        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.screenGutter,
            right: AppSpacing.screenGutter,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Set your transaction PIN',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'This 4-digit PIN protects your wallet — you\'ll be asked '
                'for it every time you confirm an order.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: pinController,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 12),
                decoration: InputDecoration(
                  labelText: 'New PIN',
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 4,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 12),
                decoration: InputDecoration(
                  labelText: 'Confirm PIN',
                  counterText: '',
                  errorText: error,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isSaving ? null : submit,
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.pureWhite,
                          ),
                        )
                      : const Text('Save PIN'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(ctx).pop(false),
                child: const Text('Not now'),
              ),
            ],
          ),
        );
      },
    ),
  );

  return result ?? false;
}
