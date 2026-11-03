import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/media/app_image.dart';
import 'cart_provider.dart';
import 'checkout_screen.dart';

/// Cart review screen — shows items grouped by vendor, allows quantity
/// adjustments and removal, displays the running subtotal, and
/// leads to checkout.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  /// Which vendor groups are expanded (by vendor ID).
  late Set<String> _expandedVendors;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return Scaffold(
        appBar: const UniflexAppBar(title: 'Your Cart'),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shopping_cart_outlined,
                      size: 36, color: theme.colorScheme.primary),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Your cart is empty',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Add items from the menu to get started.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final vendorGroups = cart.groups.values
        .where((g) => !g.isEmpty)
        .toList();
    final isMultiVendor = vendorGroups.length > 1;

    // Initialize expanded set once with the first vendor open.
    if (!_initialized && vendorGroups.isNotEmpty) {
      _expandedVendors = {vendorGroups.first.vendor.id};
      _initialized = true;
    }

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Your Cart',
        actions: [
          TextButton(
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.of(context).pop();
            },
            child: Text('Clear',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: AppColors.error)),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: 120),
        itemCount: vendorGroups.length,
        itemBuilder: (context, gi) {
          final group = vendorGroups[gi];
          final isExpanded =
              !isMultiVendor || _expandedVendors.contains(group.vendor.id);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Vendor header — tappable accordion when multi-vendor.
              if (isMultiVendor)
                InkWell(
                  onTap: () => setState(() {
                    if (_expandedVendors.contains(group.vendor.id)) {
                      _expandedVendors.remove(group.vendor.id);
                    } else {
                      _expandedVendors.add(group.vendor.id);
                    }
                  }),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.screenGutter,
                      AppSpacing.md,
                      AppSpacing.screenGutter,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.storefront,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'From ${group.vendor.name}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          '${group.items.length} item${group.items.length == 1 ? '' : 's'}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            Icons.expand_more,
                            size: 20,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        IconButton(
                          onPressed: () => ref
                              .read(cartProvider.notifier)
                              .removeVendor(group.vendor.id),
                          icon: const Icon(Icons.close, size: 18),
                          tooltip: 'Remove all from ${group.vendor.name}',
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),

              if (isExpanded) ...[
                // Pack info (if packs exist)
                if (group.packCount > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.screenGutter,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color:
                            AppColors.emerald.withValues(alpha: 0.08),
                        borderRadius:
                            BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 16, color: AppColors.emerald),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${group.packCount} pack${group.packCount > 1 ? 's' : ''}'
                            ' · ₦${group.packFee.toStringAsFixed(0)}',
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: AppColors.emerald),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Items
                ...group.items.asMap().entries.map((entry) {
                  final localIdx = entry.key;
                  final item = entry.value;
                  return _CartItemTile(
                    item: item,
                    onDecrement: () => ref
                        .read(cartProvider.notifier)
                        .removeItemFromVendor(
                            group.vendor.id,
                            item.quantity <= 1
                                ? localIdx
                                : -1), // -1 = update qty
                    onRemoveOrUpdate: (qty) {
                      if (qty <= 0) {
                        ref
                            .read(cartProvider.notifier)
                            .removeItemFromVendor(
                                group.vendor.id, localIdx);
                      } else {
                        _updateVendorItemQty(
                            ref, group.vendor.id, localIdx, qty);
                      }
                    },
                  );
                }),
              ],

              if (gi < vendorGroups.length - 1)
                const Divider(height: AppSpacing.lg),
            ],
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
                  Text('₦${cart.subtotal.toStringAsFixed(0)}',
                      style: theme.textTheme.titleSmall),
                ],
              ),
              if (cart.totalPackFee > 0) ...[
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Pack fees',
                        style: theme.textTheme.bodySmall),
                    Text(
                        '₦${cart.totalPackFee.toStringAsFixed(0)}',
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              PrimaryButton(
                label: 'Proceed to Checkout',
                icon: Icons.arrow_forward,
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CheckoutScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _updateVendorItemQty(
      WidgetRef ref, String vendorId, int localIdx, int qty) {
    final cart = ref.read(cartProvider);
    int flatIdx = 0;
    for (final entry in cart.groups.entries) {
      if (entry.key == vendorId) {
        flatIdx += localIdx;
        break;
      }
      flatIdx += entry.value.items.length;
    }
    ref.read(cartProvider.notifier).updateQuantity(flatIdx, qty);
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.onDecrement,
    required this.onRemoveOrUpdate,
  });

  final dynamic item; // CartItem
  final VoidCallback onDecrement;
  final ValueChanged<int> onRemoveOrUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenGutter,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: AppImage(
              url: item.product.imageUrl,
              keywords: 'food,meal',
              seed: item.product.id.hashCode,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.product.name,
                    style: theme.textTheme.labelLarge),
                if (item.optionsSummary.isNotEmpty)
                  Text(item.optionsSummary,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      )),
                const SizedBox(height: 4),
                Text(
                  '₦${item.unitTotal.toStringAsFixed(0)} each',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Row(
            children: [
              _SmallButton(
                icon: Icons.remove,
                onTap: () => onRemoveOrUpdate(item.quantity - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm),
                child: Text('${item.quantity}',
                    style: theme.textTheme.titleSmall),
              ),
              _SmallButton(
                icon: Icons.add,
                onTap: () => onRemoveOrUpdate(item.quantity + 1),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 56,
            child: Text(
              '₦${item.lineTotal.toStringAsFixed(0)}',
              style: theme.textTheme.labelMedium,
              textAlign: TextAlign.right,
            ),
          ),
        ],
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
