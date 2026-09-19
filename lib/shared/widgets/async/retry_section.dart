import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// Reusable "something didn't load" state with a Retry control.
///
/// Post-testing fixes, Section 5: every screen driven by a real-time
/// subscription or initial fetch (wallet balance, Kitchen Queue, order
/// tracking, job pool, etc.) used to just render nothing on failure, with
/// no way to recover short of leaving the screen. Drop this in instead of
/// a bare error Text so there's always a way to manually reload.
class RetrySection extends StatelessWidget {
  const RetrySection({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.wifi_off_outlined,
    this.compact = false,
  });

  /// Short, user-facing explanation of what failed to load.
  final String message;

  /// Called when the student/rider/admin taps Retry — typically
  /// `ref.invalidate(someProvider)`.
  final VoidCallback onRetry;
  final IconData icon;

  /// Use a smaller inline layout (icon + text + retry link in a row)
  /// instead of the default centred column, for sections embedded inside
  /// a larger scrollable screen rather than filling it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurface.withValues(alpha: 0.55);

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenGutter,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: mutedColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(message,
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedColor)),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: mutedColor),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: mutedColor),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
