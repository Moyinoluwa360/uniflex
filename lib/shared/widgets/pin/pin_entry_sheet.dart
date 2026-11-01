import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/profile/profile_service.dart';
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
///
/// Automatically detects whether the user already has a PIN. If so,
/// a "Current PIN" field is shown and the value is sent as
/// `currentPin` to [ProfileService.setTransactionPin] — required by
/// the Phase 9 `set_transaction_pin(text, text)` overload.
Future<bool> showSetPinSheet(BuildContext context, WidgetRef ref) async {
  // Check up front whether a PIN already exists so we can show the
  // "current PIN" field when changing (vs first-time setup).
  bool hasExisting = false;
  try {
    hasExisting =
        await ref.read(profileServiceProvider).hasTransactionPin();
  } catch (_) {
    // If the check itself fails, assume no existing PIN — worst case
    // the server will reject with INVALID_CURRENT_PIN and we surface it.
  }

  if (!context.mounted) return false;

  final currentPinController = TextEditingController();
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
          final currentPin = currentPinController.text.trim();

          if (hasExisting && currentPin.length != 4) {
            setState(() => error = 'Enter your current 4-digit PIN');
            return;
          }
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
            await ref.read(profileServiceProvider).setTransactionPin(
                  pin,
                  currentPin: hasExisting ? currentPin : null,
                );
            if (ctx.mounted) Navigator.of(ctx).pop(true);
          } on ProfileException catch (e) {
            setState(() {
              isSaving = false;
              error = e.message;
            });
          } catch (e) {
            setState(() {
              isSaving = false;
              error = 'Could not save PIN: ${e.toString().replaceAll('Exception: ', '')}';
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
              Text(
                hasExisting
                    ? 'Change your transaction PIN'
                    : 'Set your transaction PIN',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                hasExisting
                    ? 'Enter your current PIN, then choose a new one.'
                    : 'This 4-digit PIN protects your wallet — you\'ll be asked '
                        'for it every time you confirm an order.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (hasExisting) ...[
                TextField(
                  controller: currentPinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(letterSpacing: 12),
                  decoration: InputDecoration(
                    labelText: 'Current PIN',
                    counterText: '',
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.control),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              TextField(
                controller: pinController,
                autofocus: !hasExisting,
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
