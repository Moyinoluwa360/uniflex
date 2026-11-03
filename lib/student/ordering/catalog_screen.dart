import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/media/app_image.dart';
import 'cart_provider.dart';
import 'cart_screen.dart';
import 'pack_builder_screen.dart';
import 'product_repository.dart';

/// Vendor menu — three sections: Food (pack-first flow), Drinks, Others.
///
/// Food items route through [PackBuilderScreen] where the student picks
/// pack count first, then fills each pack. Drinks and Others are added
/// directly via inline steppers.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  /// Which non-food section is expanded: 'drinks', 'others', or null.
  String? _expandedSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendor = widget.vendor;
    final productsAsync = ref.watch(vendorProductsProvider(vendor.id));
    final cartState = ref.watch(cartProvider);

    return Scaffold(
      appBar: UniflexAppBar(
        title: vendor.name,
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.search_off_outlined,
                          size: 32, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text('No results on this menu',
                        style: theme.textTheme.titleSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Try another vendor or check back later.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Group by section. Products with null or unrecognised
          // section fall into Others with a dev-log warning.
          final foodProducts = <Product>[];
          final drinkProducts = <Product>[];
          final otherProducts = <Product>[];

          for (final p in products) {
            switch (p.section) {
              case 'food':
                foodProducts.add(p);
              case 'drinks':
                drinkProducts.add(p);
              case 'others':
                otherProducts.add(p);
              default:
                dev.log(
                  'Product "${p.name}" (${p.id}) has unknown '
                  'section "${p.section}" — showing under Others.',
                  name: 'CatalogScreen',
                );
                otherProducts.add(p);
            }
          }

          return ListView(
            padding:
                const EdgeInsets.only(top: AppSpacing.sm, bottom: 96),
            children: [
              // ── Food section (pack-first entry point) ──────────
              const _SectionHeader(title: 'Food', icon: Icons.restaurant),
              if (foodProducts.isNotEmpty)
                _FoodSectionCard(
                  vendor: vendor,
                  foodProducts: foodProducts,
                )
              else
                const _EmptySectionMessage(
                  message: 'No food items available right now.',
                ),

              // ── Drinks accordion ──────────────────────────────
              AppAccordionCard(
                leading: buildAccordionLeadingIcon(
                  context: context,
                  icon: Icons.local_cafe_outlined,
                ),
                title: 'Drinks',
                subtitle:
                    '${drinkProducts.length} item${drinkProducts.length == 1 ? '' : 's'}',
                isExpanded: _expandedSection == 'drinks',
                onTap: () => setState(() {
                  _expandedSection =
                      _expandedSection == 'drinks' ? null : 'drinks';
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: drinkProducts.isNotEmpty
                      ? drinkProducts
                          .map((p) => _ProductTile(product: p, vendor: vendor))
                          .toList()
                      : const [
                          _EmptySectionMessage(
                              message: 'No drinks available right now.'),
                        ],
                ),
              ),

              // ── Others accordion ──────────────────────────────
              AppAccordionCard(
                leading: buildAccordionLeadingIcon(
                  context: context,
                  icon: Icons.category_outlined,
                ),
                title: 'Others',
                subtitle:
                    '${otherProducts.length} item${otherProducts.length == 1 ? '' : 's'}',
                isExpanded: _expandedSection == 'others',
                onTap: () => setState(() {
                  _expandedSection =
                      _expandedSection == 'others' ? null : 'others';
                }),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: otherProducts.isNotEmpty
                      ? otherProducts
                          .map((p) => _ProductTile(product: p, vendor: vendor))
                          .toList()
                      : const [
                          _EmptySectionMessage(
                              message: 'No other items available right now.'),
                        ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: cartState.isEmpty
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CartScreen(),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.lg,
        AppSpacing.screenGutter,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: theme.textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _EmptySectionMessage extends StatelessWidget {
  const _EmptySectionMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.md,
      ),
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

/// Card that links to the pack-first food ordering flow.
class _FoodSectionCard extends ConsumerWidget {
  const _FoodSectionCard({
    required this.vendor,
    required this.foodProducts,
  });

  final Vendor vendor;
  final List<Product> foodProducts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mealCount =
        foodProducts.where((p) => p.isMeal).length;
    final proteinCount =
        foodProducts.where((p) => p.isProteinTopping).length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => PackBuilderScreen(
              vendor: vendor,
              foodProducts: foodProducts,
            ),
          ));
        },
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: AppColors.emerald.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: const Icon(Icons.inventory_2_outlined,
                    color: AppColors.emerald),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Order Food (Packs)',
                        style: theme.textTheme.labelLarge),
                    const SizedBox(height: 2),
                    Text(
                      '$mealCount meals, $proteinCount proteins/toppings'
                      ' · ₦${vendor.packPrice.toStringAsFixed(0)}/pack',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            ],
          ),
        ),
      ),
    );
  }

}

/// Product tile with inline add/stepper — used for Drinks and Others.
class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.product, required this.vendor});

  final Product product;
  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);
    // Look up this product's quantity within the vendor's group.
    final vendorGroup = cart.groups[vendor.id];
    final localIdx = vendorGroup?.items
        .indexWhere((i) => i.product.id == product.id) ?? -1;
    final quantity = localIdx >= 0 ? vendorGroup!.items[localIdx].quantity : 0;

    void addFirst() {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AppImage(
              url: product.imageUrl,
              keywords: 'food,meal,${product.section}',
              seed: product.id.hashCode,
              borderRadius: BorderRadius.circular(AppRadius.control - 2),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
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
          quantity == 0
              ? _AddButton(onTap: addFirst)
              : _QuantityStepper(
                  quantity: quantity,
                  onDecrement: () {
                    if (quantity <= 1) {
                      ref
                          .read(cartProvider.notifier)
                          .removeItemFromVendor(vendor.id, localIdx);
                    } else {
                      // Compute flat index for updateQuantity.
                      final cart = ref.read(cartProvider);
                      int flat = 0;
                      for (final e in cart.groups.entries) {
                        if (e.key == vendor.id) {
                          flat += localIdx;
                          break;
                        }
                        flat += e.value.items.length;
                      }
                      ref
                          .read(cartProvider.notifier)
                          .updateQuantity(flat, quantity - 1);
                    }
                  },
                  onIncrement: () {
                    final cart = ref.read(cartProvider);
                    int flat = 0;
                    for (final e in cart.groups.entries) {
                      if (e.key == vendor.id) {
                        flat += localIdx;
                        break;
                      }
                      flat += e.value.items.length;
                    }
                    ref
                        .read(cartProvider.notifier)
                        .updateQuantity(flat, quantity + 1);
                  },
                ),
        ],
      ),
    );
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
