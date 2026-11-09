import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/cart/cart_widgets.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/lists/app_list_group.dart';
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
    final c = context.colors;
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
                  style: AppTypography.caption(c).copyWith(
                    color: c.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: c.surfaceRaised,
                side: BorderSide(color: vendor.isUniflex ? c.brand : c.border),
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
                    Icon(AppIcons.search, size: 32, color: c.textTertiary),
                    const SizedBox(height: AppSpacing.md),
                    Text('No results on this menu',
                        style: theme.textTheme.titleSmall,
                        textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Try another vendor or check back later.',
                      style: AppTypography.meta(c),
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
            padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 96),
            children: [
              // ── Food section (pack-first entry point) ──────────
              const _SectionHeader(title: 'Food', icon: AppIcons.food),
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
                  icon: AppIcons.food,
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
                  icon: AppIcons.pack,
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
              // The cart button is one of the two places orange is allowed.
              backgroundColor: c.promoOrangeButton,
              foregroundColor: AppColors.onMedia,
              label: Text(
                'View Cart (${cartState.itemCount})',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.onMedia),
              ),
              icon: const Icon(AppIcons.cart),
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
          Icon(icon, size: 18, color: context.colors.textSecondary),
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
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.md,
      ),
      child: Text(
        message,
        style: AppTypography.meta(c).copyWith(fontStyle: FontStyle.italic),
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
    final mealCount = foodProducts.where((p) => p.isMeal).length;
    final proteinCount = foodProducts.where((p) => p.isProteinTopping).length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: AppListGroup(
        children: [
          AppListRow(
            leadingIcon: AppIcons.pack,
            title: 'Order Food (Packs)',
            subtitle: '$mealCount meals, $proteinCount proteins/toppings'
                ' · ${Money.format(vendor.packPrice)}/pack',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PackBuilderScreen(
                  vendor: vendor,
                  foodProducts: foodProducts,
                ),
              ));
            },
          ),
        ],
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
    final c = context.colors;
    final cart = ref.watch(cartProvider);
    // Look up this product's quantity within the vendor's group.
    final vendorGroup = cart.groups[vendor.id];
    final localIdx =
        vendorGroup?.items.indexWhere((i) => i.product.id == product.id) ?? -1;
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
                Text(product.name,
                    style: AppTypography.body(c)
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                if (product.description.isNotEmpty)
                  Text(
                    product.description,
                    style: AppTypography.meta(c),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                MoneyText(
                  product.basePrice,
                  style: AppTypography.body(c)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          quantity == 0
              ? AddItemButton(onTap: addFirst)
              : QuantityStepper(
                  quantity: quantity,
                  onMinus: () {
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
                  onPlus: () {
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
