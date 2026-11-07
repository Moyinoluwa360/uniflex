import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// The red message box used by every sign-up step (same look the old
/// screens had, now in one place).
class SignupErrorBanner extends StatelessWidget {
  const SignupErrorBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 20, color: colorScheme.error),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                text,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
