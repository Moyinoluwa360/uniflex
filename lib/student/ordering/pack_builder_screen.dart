import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/constants/pack_constants.dart';
import '../../shared/models/cart_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cart/cart_widgets.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/widgets/media/app_image.dart';
import '../../shared/widgets/notice/app_inline_notice.dart';
import 'cart_provider.dart';

/// Pack-first ordering flow for food items.
///
/// 1. Student chooses how many packs (stepper, min 1).
/// 2. Student fills each pack one at a time (tab switcher).
/// 3. Each pack shows Meals and Proteins/Toppings subsections.
/// 4. Meal items count toward the 8-spoon capacity limit per pack.
/// 5. Proteins/Toppings have no limit.
/// 6. "Add to Cart" adds all packs (with pack fees) to the cart.
class PackBuilderScreen extends ConsumerStatefulWidget {
  const PackBuilderScreen({
    super.key,
    required this.vendor,
    required this.foodProducts,
  });

  final Vendor vendor;
  final List<Product> foodProducts;

  @override
  ConsumerState<PackBuilderScreen> createState() => _PackBuilderScreenState();
}

class _PackBuilderScreenState extends ConsumerState<PackBuilderScreen> {
  int _packCount = 1;
  int _activePack = 0; // which pack tab is active (0-indexed)

  // packContents[packIndex] = {productId: quantity}
  late List<Map<String, int>> _packContents;

  late List<Product> _meals;
  late List<Product> _proteins;

  /// Which subsection is expanded: 'meals', 'proteins', or null.
  String? _expandedSubsection;

  @override
  void initState() {
    super.initState();
    _meals = widget.foodProducts.where((p) => p.isMeal).toList();
    _proteins = widget.foodProducts.where((p) => p.isProteinTopping).toList();
    _packContents = [<String, int>{}];
  }

  int _mealSpoonsInPack(int packIndex) {
    final contents = _packContents[packIndex];
    int spoons = 0;
    for (final entry in contents.entries) {
      final product = widget.foodProducts.firstWhere(
        (p) => p.id == entry.key,
        orElse: () => widget.foodProducts.first,
      );
      if (product.isMeal) spoons += entry.value;
    }
    return spoons;
  }

  bool _isPackEmpty(int packIndex) {
    final contents = _packContents[packIndex];
    return contents.isEmpty || contents.values.every((qty) => qty == 0);
  }

  String? _emptyPackError() {
    for (int i = 0; i < _packCount; i++) {
      if (_isPackEmpty(i)) {
        return 'Pack ${i + 1} is empty. Add food to it or remove the pack.';
      }
    }
    return null;
  }

  void _setPackCount(int count) {
    if (count < 1) return;
    setState(() {
      if (count > _packCount) {
        for (int i = _packCount; i < count; i++) {
          _packContents.add(<String, int>{});
        }
      } else if (count < _packCount) {
        _packContents.removeRange(count, _packCount);
        if (_activePack >= count) _activePack = count - 1;
      }
      _packCount = count;
    });
  }

  void _setItemQty(int packIndex, String productId, int qty) {
    setState(() {
      if (qty <= 0) {
        _packContents[packIndex].remove(productId);
      } else {
        _packContents[packIndex][productId] = qty;
      }
    });
  }

  double get _totalPackFee => _packCount * widget.vendor.packPrice;

  void _addToCart() {
    final notifier = ref.read(cartProvider.notifier);

    // Add pack items to cart as CartItems tagged with pack info.
    for (int i = 0; i < _packCount; i++) {
      final contents = _packContents[i];
      for (final entry in contents.entries) {
        if (entry.value <= 0) continue;
        final product = widget.foodProducts.firstWhere(
          (p) => p.id == entry.key,
        );
        notifier.addPackItem(
          CartItem(product: product, quantity: entry.value),
          widget.vendor,
          packIndex: i,
        );
      }
    }

    // Record pack metadata on the cart.
    notifier.setPackInfo(
      vendor: widget.vendor,
      packCount: _packCount,
      packFee: _totalPackFee,
      packContents: _packContents,
    );

    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final spoons = _mealSpoonsInPack(_activePack);
    final emptyErr = _emptyPackError();
    final canAdd = emptyErr == null;

    return Scaffold(
      appBar: UniflexAppBar(title: '${widget.vendor.name} — Food Packs'),
      body: Column(
        children: [
          // ── Pack count selector ──────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenGutter,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Column(
              children: [
                Text(
                  'How many packs of food?',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PackCountButton(
                      icon: AppIcons.remove,
                      onTap: _packCount > 1
                          ? () => _setPackCount(_packCount - 1)
                          : null,
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                      child: Text(
                        '$_packCount',
                        style: AppTypography.tabular(
                            theme.textTheme.headlineLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                        )),
                      ),
                    ),
                    _PackCountButton(
                      icon: AppIcons.add,
                      onTap: () => _setPackCount(_packCount + 1),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${Money.format(widget.vendor.packPrice)} per pack'
                  ' · Total: ${Money.format(_totalPackFee)}',
                  style: AppTypography.tabular(AppTypography.meta(c)),
                ),
              ],
            ),
          ),

          // ── Pack tabs ─────────────────────────────────────────────
          if (_packCount > 1)
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenGutter),
                itemCount: _packCount,
                itemBuilder: (_, i) {
                  final isActive = i == _activePack;
                  final isEmpty = _isPackEmpty(i);
                  return Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Pack ${i + 1}'),
                          if (isEmpty) ...[
                            const SizedBox(width: 4),
                            Icon(AppIcons.error, size: 14, color: c.dangerText),
                          ],
                        ],
                      ),
                      selected: isActive,
                      onSelected: (_) => setState(() => _activePack = i),
                    ),
                  );
                },
              ),
            ),

          // ── Pack-full warning (only visible at capacity) ──────────
          if (spoons >= kPackMealCapacity)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenGutter,
                vertical: AppSpacing.sm,
              ),
              child: AppInlineNotice.custom(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'This pack is full. Add another pack to get more.',
                        style: AppTypography.meta(c),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    AppButton(
                      label: 'Add pack',
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.small,
                      expand: false,
                      onPressed: () => _setPackCount(_packCount + 1),
                    ),
                  ],
                ),
              ),
            ),

          // ── Product list (accordion: Meals, Proteins) ─────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (_meals.isNotEmpty)
                  AppAccordionCard(
                    leading: buildAccordionLeadingIcon(
                      context: context,
                      icon: AppIcons.food,
                    ),
                    title: 'Meals',
                    subtitle:
                        '${_meals.length} item${_meals.length == 1 ? '' : 's'}',
                    isExpanded: _expandedSubsection == 'meals',
                    onTap: () => setState(() {
                      _expandedSubsection =
                          _expandedSubsection == 'meals' ? null : 'meals';
                    }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _meals
                          .map((p) => _PackProductTile(
                                product: p,
                                quantity: _packContents[_activePack][p.id] ?? 0,
                                spoonsUsed: spoons,
                                isMeal: true,
                                onChanged: (qty) =>
                                    _setItemQty(_activePack, p.id, qty),
                              ))
                          .toList(),
                    ),
                  ),
                if (_proteins.isNotEmpty)
                  AppAccordionCard(
                    leading: buildAccordionLeadingIcon(
                      context: context,
                      icon: AppIcons.pack,
                    ),
                    title: 'Proteins / Toppings',
                    subtitle:
                        '${_proteins.length} item${_proteins.length == 1 ? '' : 's'}',
                    isExpanded: _expandedSubsection == 'proteins',
                    onTap: () => setState(() {
                      _expandedSubsection =
                          _expandedSubsection == 'proteins' ? null : 'proteins';
                    }),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _proteins
                          .map((p) => _PackProductTile(
                                product: p,
                                quantity: _packContents[_activePack][p.id] ?? 0,
                                spoonsUsed: spoons,
                                isMeal: false,
                                onChanged: (qty) =>
                                    _setItemQty(_activePack, p.id, qty),
                              ))
                          .toList(),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
              if (emptyErr != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    emptyErr,
                    style: AppTypography.meta(c).copyWith(color: c.dangerText),
                    textAlign: TextAlign.center,
                  ),
                ),
              AppButton(
                label: 'Add to Cart'
                    ' ($_packCount pack${_packCount > 1 ? 's' : ''},'
                    ' ${Money.format(_totalPackFee)})',
                icon: AppIcons.cart,
                onPressed: canAdd ? _addToCart : null,
              ),
              if (_packCount > 1)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: AppButton(
                    label: 'Remove last empty pack',
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.small,
                    expand: false,
                    onPressed: _isPackEmpty(_packCount - 1)
                        ? () => _setPackCount(_packCount - 1)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PackProductTile extends StatelessWidget {
  const _PackProductTile({
    required this.product,
    required this.quantity,
    required this.spoonsUsed,
    required this.isMeal,
    required this.onChanged,
  });

  final Product product;
  final int quantity;
  final int spoonsUsed;
  final bool isMeal;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    // For meals: block adding if pack is full.
    final atCapacity = isMeal && spoonsUsed >= kPackMealCapacity;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: AppImage(
              url: product.imageUrl,
              keywords: 'food,${product.foodSubsection ?? "meal"}',
              seed: product.id.hashCode,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name, style: theme.textTheme.labelLarge),
                Text(
                  '${Money.format(product.basePrice)}'
                  '${isMeal ? ' · 1 spoon each' : ''}',
                  style: AppTypography.tabular(AppTypography.meta(c)),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (quantity == 0)
            AddItemButton(onTap: atCapacity ? null : () => onChanged(1))
          else
            _CountStepper(
              value: quantity,
              min: 0,
              maxReached: isMeal && atCapacity && quantity > 0,
              onChanged: (v) {
                if (isMeal && v > quantity && spoonsUsed >= kPackMealCapacity) {
                  return; // blocked
                }
                onChanged(v);
              },
            ),
        ],
      ),
    );
  }
}

class _PackCountButton extends StatelessWidget {
  const _PackCountButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      child: Material(
        color: Colors.transparent,
        shape: CircleBorder(
          side: BorderSide(color: enabled ? c.borderStrong : c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 52,
            height: 52,
            child: Icon(
              icon,
              size: 28,
              color: enabled ? c.textPrimary : c.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

class _CountStepper extends StatelessWidget {
  const _CountStepper({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.maxReached = false,
  });

  final int value;
  final int min;
  final bool maxReached;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return QuantityStepper(
      quantity: value,
      onMinus: value > min ? () => onChanged(value - 1) : null,
      onPlus: maxReached ? null : () => onChanged(value + 1),
    );
  }
}
