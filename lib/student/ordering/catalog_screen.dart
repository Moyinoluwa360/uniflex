import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import 'cart_provider.dart';
import 'cart_screen.dart';
import 'product_repository.dart';

/// Vendor menu — post-testing fixes, Section 11: every product is its own
/// independently orderable item with its own quantity stepper, added to
/// the cart directly from this list. This replaces the old
/// quantity→protein→extras→drink combo-builder wizard (removed, not kept
/// alongside it) — Jollof Rice, Chicken, and a drink are each their own
/// catalog item now, the way a normal food-ordering app works. Drinks
/// live in their own category section, added the same way as everything
/// else.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(vendorProductsProvider(vendor.id));
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(vendor.name),
        actions: [
          if (vendor.badgeLabel != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Chip(
                label: Text(
                  vendor.badgeLabel!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: vendor.isUniflex
                        ? AppColors.pureWhite
                        : theme.colorScheme.onSurface,
                  ),
                ),
                backgroundColor: vendor.isUniflex
                    ? AppColors.emerald
                    : theme.colorScheme.surfaceContainerHighest,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load menu.',
          onRetry: () => ref.invalidate(vendorProductsProvider(vendor.id)),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No items available right now.'));
          }

          // Group by category, preserving the order they come back from the DB.
          final categories = <String>[];
          final byCategory = <String, List<Product>>{};
          for (final p in products) {
            if (!byCategory.containsKey(p.category)) {
              categories.add(p.category);
              byCategory[p.category] = [];
            }
            byCategory[p.category]!.add(p);
          }

          return ListView.builder(
            padding: const EdgeInsets.only(
              top: AppSpacing.sm,
              bottom: 96, // space for the cart FAB
            ),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final cat = categories[i];
              final items = byCategory[cat]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                    ),
                    child: Text(cat, style: theme.textTheme.titleSmall),
                  ),
                  ...items.map(
                    (product) => _ProductTile(product: product, vendor: vendor),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: cartState.isEmpty ||
              (cartState.vendor?.id != vendor.id)
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CartScreen(vendor: vendor),
                ),
              ),
              backgroundColor: AppColors.orange,
              foregroundColor: AppColors.pureWhite,
              label: Text(
                'View Cart (${cartState.itemCount})',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.pureWhite),
              ),
              icon: const Icon(Icons.shopping_cart_outlined),
            ),
    );
  }
}

class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product, required this.vendor});

  final Product product;
  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    final wrongVendor = cart.vendor != null && cart.vendor!.id != vendor.id;
    final index = cart.items.indexWhere((i) => i.product.id == product.id);
    final quantity = index >= 0 ? cart.items[index].quantity : 0;

    void addFirst() {
      if (wrongVendor) {
        _confirmClearCart(context, ref);
        return;
      }
      ref
          .read(cartProvider.notifier)
          .addItem(CartItem(product: product, quantity: 1), vendor);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                if (product.description.isNotEmpty)
                  Text(
                    product.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '₦${product.basePrice.toStringAsFixed(0)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (product.requiresPack) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.inventory_2_outlined,
                          size: 13,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          quantity == 0
              ? _AddButton(onTap: addFirst)
              : _QuantityStepper(
                  quantity: quantity,
                  onDecrement: () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(index, quantity - 1),
                  onIncrement: () => ref
                      .read(cartProvider.notifier)
                      .updateQuantity(index, quantity + 1),
                ),
        ],
      ),
    );
  }

  Future<void> _confirmClearCart(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start a new cart?'),
        content: Text(
          'Your cart has items from another vendor. Adding "${product.name}" '
          'will clear it and start a new order from ${vendor.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear & Add'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref.read(cartProvider.notifier).clear();
      ref
          .read(cartProvider.notifier)
          .addItem(CartItem(product: product, quantity: 1), vendor);
    }
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: const BoxDecoration(
          color: AppColors.orange,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.add, color: AppColors.pureWhite, size: 20),
      ),
    );
  }
}

/// Inline "- qty +" stepper shown once an item is in the cart — the
/// normal food-ordering-app pattern this section asks for, replacing the
/// old "tap to open a wizard" flow.
class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({
    required this.quantity,
    required this.onDecrement,
    required this.onIncrement,
  });

  final int quantity;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.remove, size: 16),
            color: theme.colorScheme.primary,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          SizedBox(
            width: 20,
            child: Text(
              '$quantity',
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge,
            ),
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add, size: 16),
            color: theme.colorScheme.primary,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}
