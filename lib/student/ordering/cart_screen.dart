import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
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
  /// Which vendor groups are expanded (by vendor ID). All start closed.
  final Set<String> _expandedVendors = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notifier = ref.read(cartProvider.notifier);
      final wasExpired =
          notifier.expiredOnLoad || notifier.checkAndClearIfExpired();
      if (wasExpired) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your cart was cleared after 1 hour.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

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

          // Single vendor: flat list with no accordion.
          if (!isMultiVendor) {
            return _VendorItemList(
              group: group,
              onItemUpdate: (localIdx, qty) {
                if (qty <= 0) {
                  ref
                      .read(cartProvider.notifier)
                      .removeItemFromVendor(group.vendor.id, localIdx);
                } else {
                  _updateVendorItemQty(ref, group.vendor.id, localIdx, qty);
                }
              },
            );
          }

          // Multi-vendor: AppAccordionCard per vendor.
          final vendorSubtotal = group.totalWithPacks;

          return AppAccordionCard(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: AppImage(
                url: group.vendor.imageUrl,
                keywords: 'restaurant,food',
                seed: group.vendor.id.hashCode,
                borderRadius: BorderRadius.circular(10),
                icon: Icons.storefront_outlined,
              ),
            ),
            title: group.vendor.name,
            subtitle:
                '${group.items.length} item${group.items.length == 1 ? '' : 's'}'
                ' · ₦${vendorSubtotal.toStringAsFixed(0)}',
            isExpanded: isExpanded,
            onTap: () => setState(() {
              if (_expandedVendors.contains(group.vendor.id)) {
                _expandedVendors.remove(group.vendor.id);
              } else {
                // Only one vendor open at a time.
                _expandedVendors
                  ..clear()
                  ..add(group.vendor.id);
              }
            }),
            trailingAction: IconButton(
              icon: const Icon(Icons.close_rounded, size: 18),
              tooltip: 'Remove ${group.vendor.name} from cart',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('Remove ${group.vendor.name}?'),
                    content: Text(
                      'This removes all ${group.items.length} '
                      'item${group.items.length == 1 ? '' : 's'} '
                      'from ${group.vendor.name}.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(
                          'Remove',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  ref
                      .read(cartProvider.notifier)
                      .removeVendor(group.vendor.id);
                }
              },
            ),
            child: _VendorItemList(
              group: group,
              onItemUpdate: (localIdx, qty) {
                if (qty <= 0) {
                  ref
                      .read(cartProvider.notifier)
                      .removeItemFromVendor(group.vendor.id, localIdx);
                } else {
                  _updateVendorItemQty(ref, group.vendor.id, localIdx, qty);
                }
              },
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

/// Pack info banner + item list for a single vendor group.
/// Used both as a direct list child (single-vendor) and as the accordion
/// content (multi-vendor).
class _VendorItemList extends ConsumerWidget {
  const _VendorItemList({
    required this.group,
    required this.onItemUpdate,
  });

  final VendorCartGroup group;
  final void Function(int localIdx, int qty) onItemUpdate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group.packCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              0,
            ),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 16, color: AppColors.emerald),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${group.packCount} pack${group.packCount > 1 ? 's' : ''}'
                    ' · ₦${group.packFee.toStringAsFixed(0)}',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: AppColors.emerald),
                  ),
                ],
              ),
            ),
          ),
        ...group.items.asMap().entries.map((entry) {
          final localIdx = entry.key;
          final item = entry.value;
          return _CartItemTile(
            item: item,
            onDecrement: () => onItemUpdate(
                localIdx, item.quantity <= 1 ? 0 : item.quantity - 1),
            onRemoveOrUpdate: (qty) => onItemUpdate(localIdx, qty),
          );
        }),
      ],
    );
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
