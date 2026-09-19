import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import 'cart_provider.dart';
import 'cart_screen.dart';
import 'meal_customization_screen.dart';
import 'product_repository.dart';

/// Vendor menu — products grouped by category. A floating "View Cart"
/// button appears whenever the cart is non-empty.
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
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            child: Text('Could not load menu: $e'),
          ),
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

          // Drinks products — passed to customization screen for drink step
          final drinkProducts =
              products.where((p) => p.category == 'Drinks').toList();

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
                    (product) => _ProductTile(
                      product: product,
                      vendor: vendor,
                      drinkProducts: drinkProducts,
                    ),
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

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.vendor,
    required this.drinkProducts,
  });

  final Product product;
  final Vendor vendor;
  final List<Product> drinkProducts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MealCustomizationScreen(
            product: product,
            vendor: vendor,
            drinkProducts: drinkProducts,
          ),
        ),
      ),
      child: Padding(
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
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  Text(
                    '₦${product.basePrice.toStringAsFixed(0)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Center(
                    child: Icon(
                      Icons.restaurant_outlined,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      size: 32,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: AppColors.orange,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: AppColors.pureWhite,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
