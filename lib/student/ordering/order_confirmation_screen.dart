import 'package:flutter/material.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/tracking/pin_digit_boxes.dart';
import '../tracking/order_tracking_screen.dart';

/// Step 9 — order confirmation. Shows the placed order's reference,
/// items summary, and estimated time, then routes to the tracking screen.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            children: [
              const Spacer(),

              // Success mark: plain brand circle with a check.
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: c.brand,
                  shape: BoxShape.circle,
                ),
                child: Icon(AppIcons.check, color: c.onBrand, size: 52),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Order placed!',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(order.shortId, style: AppTypography.title(c)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'from ${order.vendorName ?? 'Uniflex'}',
                style: AppTypography.meta(c),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Order details card
              AppListGroup(
                children: [
                  if (order.estimatedTime != null)
                    AppListRow(
                      leadingIcon: AppIcons.clock,
                      title: order.estimatedTime!,
                      subtitle: 'Estimated time',
                      showChevron: false,
                    ),
                  AppListRow(
                    leadingIcon: order.isForDelivery
                        ? AppIcons.delivery
                        : AppIcons.vendor,
                    title: order.isForDelivery
                        ? (order.deliveryLocation ?? '—')
                        : 'Collect from ${order.vendorName ?? 'Uniflex'}',
                    subtitle: order.isForDelivery ? 'Delivery to' : 'Pickup',
                    showChevron: false,
                  ),
                  AppListRow(
                    leadingIcon: AppIcons.receipt,
                    title: Money.format(order.totalAmount),
                    subtitle: 'Total',
                    showChevron: false,
                  ),
                ],
              ),

              // Delivery PIN card — shown only for delivery orders
              if (order.isForDelivery && order.deliveryPin != null) ...[
                const SizedBox(height: AppSpacing.md),
                _DeliveryPinCard(pin: order.deliveryPin!),
              ],

              const Spacer(),

              AppButton(
                label: 'Track Order',
                icon: AppIcons.location,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingScreen(order: order),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Back to Home',
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  // Pop until we're back at the root (the shell)
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prominent PIN card shown to the student after placing a delivery order.
class _DeliveryPinCard extends StatelessWidget {
  const _DeliveryPinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: double.infinity,
      child: AppCard(
        child: Column(
          children: [
            Row(
              children: [
                Icon(AppIcons.lock, color: c.textSecondary, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Delivery PIN',
                  style: AppTypography.meta(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            PinDigitBoxes(pin: pin, copiedMessage: 'PIN copied to clipboard'),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Show this PIN to your rider when they arrive.\nDo not share it until delivery.',
              textAlign: TextAlign.center,
              style: AppTypography.meta(c),
            ),
          ],
        ),
      ),
    );
  }
}
