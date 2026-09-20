import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/buttons/secondary_button.dart';
import '../tracking/order_tracking_screen.dart';

/// Step 9 — order confirmation. Shows the placed order's reference,
/// items summary, and estimated time, then routes to the tracking screen.
class OrderConfirmationScreen extends StatelessWidget {
  const OrderConfirmationScreen({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            children: [
              const Spacer(),

              // Success icon with soft brand glow (board: radial emerald halo)
              Container(
                width: 128,
                height: 128,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.emerald.withValues(alpha: 0.12),
                ),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: AppColors.pureWhite,
                    size: 52,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Order placed!',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                order.shortId,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'from ${order.vendorName ?? 'Uniflex'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),

              const SizedBox(height: AppSpacing.xl),

              // Order details card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.estimatedTime != null)
                      _DetailRow(
                        icon: Icons.schedule_outlined,
                        label: 'Estimated time',
                        value: order.estimatedTime!,
                        theme: theme,
                      ),
                    _DetailRow(
                      icon: order.isForDelivery
                          ? Icons.delivery_dining_outlined
                          : Icons.storefront_outlined,
                      label: order.isForDelivery ? 'Delivery to' : 'Pickup',
                      value: order.isForDelivery
                          ? (order.deliveryLocation ?? '—')
                          : 'Collect from ${order.vendorName ?? 'Uniflex'}',
                      theme: theme,
                    ),
                    _DetailRow(
                      icon: Icons.receipt_outlined,
                      label: 'Total',
                      value: '₦${order.totalAmount.toStringAsFixed(0)}',
                      theme: theme,
                    ),
                  ],
                ),
              ),

              // Delivery PIN card — shown only for delivery orders
              if (order.isForDelivery && order.deliveryPin != null) ...[
                const SizedBox(height: AppSpacing.md),
                _DeliveryPinCard(pin: order.deliveryPin!, theme: theme),
              ],

              const Spacer(),

              PrimaryButton(
                label: 'Track Order',
                icon: Icons.location_on_outlined,
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingScreen(order: order),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Back to Home',
                onPressed: () {
                  // Pop until we're back at the root (the shell)
                  Navigator.of(context)
                      .popUntil((route) => route.isFirst);
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
  const _DeliveryPinCard({required this.pin, required this.theme});

  final String pin;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline,
                  color: AppColors.emerald, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Delivery PIN',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.emerald,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('PIN copied to clipboard')),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  pin,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 12,
                    color: AppColors.emerald,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(Icons.copy_outlined,
                    size: 16, color: AppColors.emerald),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Show this PIN to your rider when they arrive.\nDo not share it until delivery.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.theme,
  });
  final IconData icon;
  final String label;
  final String value;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
