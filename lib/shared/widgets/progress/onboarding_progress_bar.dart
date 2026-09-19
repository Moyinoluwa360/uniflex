import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';

/// The back-button + progress-bar + "n / total" header used by both
/// onboarding steps (Create Account, Complete Your Profile), per the
/// design handoff.
class OnboardingProgressHeader extends StatelessWidget {
  const OnboardingProgressHeader({
    super.key,
    required this.step,
    required this.totalSteps,
    this.onBack,
  });

  final int step;
  final int totalSteps;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.xs),
            child: LinearProgressIndicator(
              value: step / totalSteps,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          '$step / $totalSteps',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
        icon: const Icon(Icons.arrow_back),
      ),
    );
  }
}
