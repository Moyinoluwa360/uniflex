import 'package:flutter/material.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../tracking/errand_tracking_screen.dart';

/// Shown after a successful errand placement.
///
/// Replaces the generic [OrderConfirmationScreen] for errands because:
///   • wording should be errand-specific ("A rider will call you…")
///   • "Track" should go to [ErrandTrackingScreen], not [OrderTrackingScreen]
class ErrandConfirmationScreen extends StatelessWidget {
  const ErrandConfirmationScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Errand sent'),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.brand,
              ),
              child: Icon(AppIcons.check, color: c.onBrand, size: 40),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Your errand has been sent!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'A rider will accept your errand and call you to sort out the details.',
              style: AppTypography.meta(c),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            // Order reference
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Text(
                'Errand ID: ${order.shortId}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Track errand',
              icon: AppIcons.location,
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => ErrandTrackingScreen(order: order),
                  ),
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Back to home',
              variant: AppButtonVariant.text,
              onPressed: () {
                // Pop back to root (home screen).
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}
