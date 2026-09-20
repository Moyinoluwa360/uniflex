import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../buttons/primary_button.dart';

/// Full-screen offline state (Design Board 56 — "Connection lost, cart
/// saved").
///
/// A reusable, purely visual page: shows the offline illustration, a
/// title/subtitle, and a Retry button wired to [onRetry]. Callers decide
/// when to show it (e.g. after a connectivity check) — this widget itself
/// performs no connectivity reads so it stays logic-free.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({
    super.key,
    required this.onRetry,
    this.title = "You're offline",
    this.message =
        'Connection lost — your cart is saved. Check your data or Wi-Fi and try again.',
    this.retryLabel = 'Try again',
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.wifi_off_outlined,
                    size: 40,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: retryLabel,
                icon: Icons.refresh,
                onPressed: onRetry,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
