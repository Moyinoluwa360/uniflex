import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import 'cart_provider.dart';

/// Meal customisation — covers steps 2–5 of the ordering flow:
///   step 2: quantity
///   step 3: protein choice (radio, if the product has protein options)
///   step 4: extras (checkboxes, if the product has extra options)
///   step 5: drink add-on (select one drink from the vendor's drink catalog)
///
/// "Add to Cart" adds the main item (with protein + extras baked into
/// selectedOptions) and, if a drink was chosen, a separate CartItem for
/// that drink at the drink's own base price.
class MealCustomizationScreen extends ConsumerStatefulWidget {
  const MealCustomizationScreen({
    super.key,
    required this.product,
    required this.vendor,
    required this.drinkProducts,
  });

  final Product product;
  final Vendor vendor;

  /// Drink products from the same vendor, shown in the drink step.
  final List<Product> drinkProducts;

  @override
  ConsumerState<MealCustomizationScreen> createState() =>
      _MealCustomizationScreenState();
}

class _MealCustomizationScreenState
    extends ConsumerState<MealCustomizationScreen> {
  int _quantity = 1;
  ProductOption? _selectedProtein;
  final Set<ProductOption> _selectedExtras = {};
  Product? _selectedDrink;

  double get _unitTotal {
    double total = widget.product.basePrice;
    if (_selectedProtein != null) total += _selectedProtein!.priceDelta;
    for (final extra in _selectedExtras) {
      total += extra.priceDelta;
    }
    return total;
  }

  double get _orderTotal {
    double total = _unitTotal * _quantity;
    if (_selectedDrink != null) total += _selectedDrink!.basePrice;
    return total;
  }

  void _addToCart() {
    final cart = ref.read(cartProvider.notifier);

    // Build selected options list
    final options = <SelectedOption>[];
    if (_selectedProtein != null) {
      options.add(SelectedOption(
        group: 'protein',
        name: _selectedProtein!.name,
        priceDelta: _selectedProtein!.priceDelta,
      ));
    }
    for (final extra in _selectedExtras) {
      options.add(SelectedOption(
        group: 'extra',
        name: extra.name,
        priceDelta: extra.priceDelta,
      ));
    }

    cart.addItem(
      CartItem(
        product: widget.product,
        quantity: _quantity,
        selectedOptions: options,
      ),
      widget.vendor,
    );

    // Add drink as a separate cart item if selected
    if (_selectedDrink != null) {
      cart.addItem(
        CartItem(product: _selectedDrink!, quantity: 1),
        widget.vendor,
      );
    }

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${widget.product.name} added to cart'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proteinOptions = widget.product.proteinOptions;
    final extraOptions = widget.product.extraOptions;

    return Scaffold(
      appBar: AppBar(title: Text(widget.product.name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image placeholder
            Container(
              width: double.infinity,
              height: 160,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.restaurant,
                    size: 48,
                    color: theme.colorScheme.primary.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    widget.product.name,
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),

            if (widget.product.description.isNotEmpty) ...[
              Text(
                widget.product.description,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],

            Text(
              '₦${widget.product.basePrice.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),

            const Divider(height: AppSpacing.xl),

            // ── Step 2: Quantity ─────────────────────────────────────
            const _SectionLabel('Quantity'),
            const SizedBox(height: AppSpacing.sm),
            _QuantitySelector(
              quantity: _quantity,
              onChanged: (q) => setState(() => _quantity = q),
            ),

            // ── Step 3: Protein ──────────────────────────────────────
            if (proteinOptions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('Choose your protein'),
              const _SectionSubLabel('Select one • Required'),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<ProductOption>(
                groupValue: _selectedProtein,
                onChanged: (v) => setState(() => _selectedProtein = v),
                child: Column(
                  children: proteinOptions.map((opt) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Radio<ProductOption>(value: opt),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(opt.name,
                                style: theme.textTheme.bodyMedium),
                          ),
                          if (opt.priceDelta != 0)
                            Text(
                              opt.priceDelta > 0
                                  ? '+₦${opt.priceDelta.toStringAsFixed(0)}'
                                  : '−₦${(-opt.priceDelta).toStringAsFixed(0)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: opt.priceDelta > 0
                                    ? AppColors.orange
                                    : AppColors.emerald,
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            // ── Step 4: Extras ───────────────────────────────────────
            if (extraOptions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('Add extras'),
              const _SectionSubLabel('Select as many as you like'),
              const SizedBox(height: AppSpacing.sm),
              ...extraOptions.map(
                (opt) => CheckboxListTile(
                  value: _selectedExtras.contains(opt),
                  onChanged: (checked) => setState(() {
                    if (checked == true) {
                      _selectedExtras.add(opt);
                    } else {
                      _selectedExtras.remove(opt);
                    }
                  }),
                  title: Text(opt.name, style: theme.textTheme.bodyMedium),
                  secondary: Text(
                    '+₦${opt.priceDelta.toStringAsFixed(0)}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.orange),
                  ),
                  activeColor: AppColors.emerald,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],

            // ── Step 5: Drink ────────────────────────────────────────
            if (widget.drinkProducts.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(),
              const SizedBox(height: AppSpacing.md),
              const _SectionLabel('Add a drink'),
              const _SectionSubLabel('Optional'),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<Product?>(
                groupValue: _selectedDrink,
                onChanged: (v) => setState(() => _selectedDrink = v),
                child: Column(
                  children: [
                    // None option
                    GestureDetector(
                      onTap: () => setState(() => _selectedDrink = null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            const Radio<Product?>(
                              value: null,
                              activeColor: AppColors.emerald,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'No drink',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ...widget.drinkProducts.map(
                      (drink) => GestureDetector(
                        onTap: () => setState(() => _selectedDrink = drink),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Radio<Product?>(
                                value: drink,
                                activeColor: AppColors.emerald,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  drink.name,
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              Text(
                                '+₦${drink.basePrice.toStringAsFixed(0)}',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: AppColors.orange),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),

      // ── Sticky bottom bar ──────────────────────────────────────────────
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
                  Text('Order total', style: theme.textTheme.bodyMedium),
                  Text(
                    '₦${_orderTotal.toStringAsFixed(0)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Add to Cart',
                icon: Icons.shopping_cart_outlined,
                onPressed:
                    (widget.product.hasProteinOptions && _selectedProtein == null)
                        ? null
                        : _addToCart,
              ),
              if (widget.product.hasProteinOptions && _selectedProtein == null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    'Please choose a protein to continue',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleSmall);
}

class _SectionSubLabel extends StatelessWidget {
  const _SectionSubLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.5),
            ),
      );
}

class _QuantitySelector extends StatelessWidget {
  const _QuantitySelector({
    required this.quantity,
    required this.onChanged,
  });

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        _QtyButton(
          icon: Icons.remove,
          onTap: quantity > 1 ? () => onChanged(quantity - 1) : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Text(
            '$quantity',
            style: theme.textTheme.titleMedium,
          ),
        ),
        _QtyButton(
          icon: Icons.add,
          onTap: () => onChanged(quantity + 1),
        ),
      ],
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: onTap != null
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Icon(
          icon,
          size: 20,
          color: onTap != null
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}

