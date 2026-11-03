import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../buttons/primary_button.dart';

/// Shows a modal bottom sheet with [message] and a "Continue" button.
/// Returns `true` when the student taps Continue, `false` on dismiss.
Future<bool> showAcknowledgmentSheet(
  BuildContext context, {
  required String message,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.info_outline,
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: 'Continue',
                onPressed: () => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      );
    },
  );
  return result == true;
}
