import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import 'cart_provider.dart';
import 'checkout_screen.dart';

/// Cart review screen — shows items in the cart, allows quantity
/// adjustments and removal, displays the running subtotal, and
/// leads to checkout.
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Your Cart')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.shopping_cart_outlined,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Your cart is empty', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Add items from the menu to get started.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.of(context).pop();
            },
            child: Text(
              'Clear',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.only(
          top: AppSpacing.sm,
          bottom: 120,
        ),
        itemCount: cart.items.length,
        separatorBuilder: (_, __) => const Divider(
          indent: AppSpacing.screenGutter,
          endIndent: AppSpacing.screenGutter,
          height: 1,
        ),
        itemBuilder: (context, i) {
          final item = cart.items[i];
          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                // Item info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: theme.textTheme.labelLarge,
                      ),
                      if (item.optionsSummary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.optionsSummary,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        '₦${item.unitTotal.toStringAsFixed(0)} each',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Quantity controls
                Row(
                  children: [
                    _SmallButton(
                      icon: Icons.remove,
                      onTap: () => ref
                          .read(cartProvider.notifier)
                          .updateQuantity(i, item.quantity - 1),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      child: Text(
                        '${item.quantity}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    _SmallButton(
                      icon: Icons.add,
                      onTap: () => ref
                          .read(cartProvider.notifier)
                          .updateQuantity(i, item.quantity + 1),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                // Line total
                SizedBox(
                  width: 64,
                  child: Text(
                    '₦${item.lineTotal.toStringAsFixed(0)}',
                    style: theme.textTheme.labelMedium,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Subtotal', style: theme.textTheme.bodyMedium),
                  Text(
                    '₦${cart.subtotal.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Proceed to Checkout',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CheckoutScreen(vendor: vendor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Icon(icon, size: 16, color: theme.colorScheme.primary),
      ),
    );
  }
}
