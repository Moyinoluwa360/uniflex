import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/cart/cart_widgets.dart';
import '../../shared/models/vendor.dart';
import '../../shared/widgets/format/money.dart';
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
      // An expired cart is cleared silently — no message.
      ref.read(cartProvider.notifier).checkAndClearIfExpired();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                Icon(AppIcons.cart, size: 36, color: c.textTertiary),
                const SizedBox(height: AppSpacing.md),
                Text('Your cart is empty', style: AppTypography.title(c)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Add items from the menu to get started.',
                  textAlign: TextAlign.center,
                  style: AppTypography.meta(c),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final vendorGroups = cart.groups.values.where((g) => !g.isEmpty).toList();
    final isMultiVendor = vendorGroups.length > 1;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Your Cart',
        actions: [
          AppButton(
            label: 'Clear',
            variant: AppButtonVariant.quietDanger,
            size: AppButtonSize.small,
            expand: false,
            onPressed: () {
              ref.read(cartProvider.notifier).clear();
              Navigator.of(context).pop();
            },
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
            return Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenGutter),
              child: AppCard(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: _VendorItemList(
                  group: group,
                  inCard: true,
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
              ),
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
                ' · ${Money.format(vendorSubtotal)}',
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
              icon: Icon(AppIcons.close, size: 18, color: c.textTertiary),
              tooltip: 'Remove ${group.vendor.name} from cart',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: () async {
                final ok = await AppDialog.show(
                  context,
                  title: 'Remove ${group.vendor.name}?',
                  body: 'This removes all ${group.items.length} '
                      'item${group.items.length == 1 ? '' : 's'} '
                      'from ${group.vendor.name}.',
                  secondaryLabel: 'Cancel',
                  confirmLabel: 'Remove',
                  destructive: true,
                );
                if (ok == true) {
                  ref.read(cartProvider.notifier).removeVendor(group.vendor.id);
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
              CartTotalRow(
                  label: 'Subtotal', amount: cart.subtotal, strong: true),
              if (cart.totalPackFee > 0) ...[
                const SizedBox(height: 4),
                CartTotalRow(label: 'Pack fees', amount: cart.totalPackFee),
              ],
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Proceed to Checkout',
                icon: AppIcons.forward,
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

/// Pack info line + item list for a single vendor group.
/// Used both as a direct list child (single-vendor) and as the accordion
/// content (multi-vendor).
class _VendorItemList extends ConsumerWidget {
  const _VendorItemList({
    required this.group,
    required this.onItemUpdate,
    this.inCard = false,
  });

  final VendorCartGroup group;
  final void Function(int localIdx, int qty) onItemUpdate;

  /// Inside an `AppCard` the rows use the card's own 16px side padding.
  final bool inCard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final side = inCard ? AppSpacing.md : AppSpacing.screenGutter;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (group.packCount > 0)
          Padding(
            padding: EdgeInsets.fromLTRB(side, AppSpacing.sm, side, 0),
            child: Row(
              children: [
                Icon(AppIcons.pack, size: 16, color: c.textSecondary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${group.packCount} pack${group.packCount > 1 ? 's' : ''}'
                  ' · ${Money.format(group.packFee)}',
                  style: AppTypography.tabular(AppTypography.meta(c)),
                ),
              ],
            ),
          ),
        ...group.items.asMap().entries.map((entry) {
          final localIdx = entry.key;
          final item = entry.value;
          return _CartItemTile(
            item: item,
            // Fixed-menu vendors: at most kFixedMenuMaxQty of one item.
            maxQuantity: group.vendor.isFixedMenu ? kFixedMenuMaxQty : null,
            padding:
                EdgeInsets.symmetric(horizontal: side, vertical: AppSpacing.sm),
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
    required this.onRemoveOrUpdate,
    required this.padding,
    this.maxQuantity,
  });

  final int? maxQuantity;
  final dynamic item; // CartItem
  final ValueChanged<int> onRemoveOrUpdate;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return CartItemRow(
      padding: padding,
      leading: SizedBox(
        width: 48,
        height: 48,
        child: AppImage(
          url: item.product.imageUrl,
          keywords: 'food,meal',
          seed: item.product.id.hashCode,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      title: item.product.name as String,
      options: item.optionsSummary as String,
      unitLine: '${Money.format(item.unitTotal as num)} each',
      quantity: item.quantity as int,
      onMinus: () => onRemoveOrUpdate(item.quantity - 1),
      onPlus: () => onRemoveOrUpdate(item.quantity + 1),
      plusEnabled: maxQuantity == null || (item.quantity as int) < maxQuantity!,
      lineTotal: item.lineTotal as num,
    );
  }
}
