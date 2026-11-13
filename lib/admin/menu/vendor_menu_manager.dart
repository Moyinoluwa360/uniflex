import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';
import 'menu_section.dart';
import 'product_form_screen.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/widgets/format/money.dart';

/// THE menu-management screen (Pack 4C). Uniflex's own menu and every
/// partner vendor's menu are this one widget — they only differ by
/// [vendorId] and [title], so a fix or feature lands in both at once.
///
/// Four sections — Meals, Proteins / Toppings, Drinks, Others — each with its
/// own "+ Add" that opens the item form already set to that section (no
/// category to pick). Per item: availability switch, edit, delete (hides the
/// item; old orders keep working), photo and price. The AppBar has the
/// vendor's pack price.
class VendorMenuManager extends ConsumerWidget {
  const VendorMenuManager({
    super.key,
    required this.vendorId,
    required this.title,
    this.fixedMenu = false,
  });

  final String vendorId;
  final String title;

  /// A fixed-menu vendor (Pack 1 / Part 3): items grouped by the admin's own
  /// categories, one "+ Add item", no pack price and no pack sections.
  final bool fixedMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(adminVendorProductsProvider(vendorId));

    return Scaffold(
      appBar: UniflexAppBar(
        title: title,
        actions: [
          if (!fixedMenu)
            IconButton(
              icon: const Icon(Icons.inventory_2_outlined),
              tooltip: 'Pack price',
              onPressed: () => _editPackPrice(context, ref),
            ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load the menu.',
          onRetry: () => ref.invalidate(adminVendorProductsProvider(vendorId)),
        ),
        data: (products) => fixedMenu
            ? FixedMenuBody(
                products: products,
                onAdd: () => _openForm(context, ref, null, MenuSection.meals,
                    categories: _categories(products)),
                onEdit: (p) => _openForm(context, ref, p, MenuSection.meals,
                    categories: _categories(products)),
                onDelete: (p) => _confirmDelete(context, ref, p),
                onToggle: (p, v) => _toggle(context, ref, p, v),
              )
            : _MenuBody(
                products: products,
                onAdd: (s) => _openForm(context, ref, null, s),
                onEdit: (p) => _openForm(context, ref, p, MenuSection.of(p)),
                onDelete: (p) => _confirmDelete(context, ref, p),
                onToggle: (p, v) => _toggle(context, ref, p, v),
              ),
      ),
    );
  }

  static List<String> _categories(List<Product> products) => (products
      .map((p) => p.category.trim())
      .where((c) => c.isNotEmpty)
      .toSet()
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())));

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    Product? product,
    MenuSection section, {
    List<String> categories = const [],
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(
          vendorId: vendorId,
          product: product,
          initialSection: section,
          fixedMenu: fixedMenu,
          categorySuggestions: categories,
        ),
      ),
    );
    if (saved == true) ref.invalidate(adminVendorProductsProvider(vendorId));
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Remove item?',
      body: 'Remove "${product.name}" from the menu? Students will no longer '
          'see it. Past orders are not affected.',
      secondaryLabel: 'Cancel',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteProduct(product.id);
      ref.invalidate(adminVendorProductsProvider(vendorId));
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not remove the item. ${AppErrorMapper.map(e)}');
      }
    }
  }

  /// Switches availability ONLY. (The old toggle re-saved the whole item and
  /// silently dropped its section for partner vendors.)
  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    Product product,
    bool available,
  ) async {
    try {
      await ref
          .read(adminServiceProvider)
          .setProductAvailability(product.id, available);
      ref.invalidate(adminVendorProductsProvider(vendorId));
    } catch (e) {
      if (context.mounted) {
        _snack(context, 'Could not update the item. ${AppErrorMapper.map(e)}');
      }
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// The per-pack price students pay at checkout for this vendor.
  Future<void> _editPackPrice(BuildContext context, WidgetRef ref) async {
    final vendors = ref.read(allVendorsProvider).valueOrNull ?? const [];
    Vendor? vendor;
    for (final v in vendors) {
      if (v.id == vendorId) vendor = v;
    }
    if (vendor == null) {
      _snack(context, 'Vendor details are still loading. Try again.');
      return;
    }
    final v = vendor;
    final controller =
        TextEditingController(text: v.packPrice.toStringAsFixed(0));
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) {
        var saving = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.screenGutter,
              right: AppSpacing.screenGutter,
              top: AppSpacing.lg,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${v.name} pack price',
                      style: Theme.of(ctx).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Charged per pack when a student uses packs at checkout.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppTextField(
                    controller: controller,
                    hint: 'Pack price (₦)',
                    keyboardType: TextInputType.number,
                    validator: (t) {
                      final price = double.tryParse(t?.trim() ?? '');
                      if (price == null || price < 0) {
                        return 'Enter a valid price';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppButton(
                    label: 'Save',
                    icon: Icons.check,
                    isLoading: saving,
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      setSheet(() => saving = true);
                      try {
                        await ref.read(adminServiceProvider).upsertVendor(
                              id: v.id,
                              name: v.name,
                              description: v.description,
                              isActive: v.isActive,
                              badgeLabel: v.badgeLabel,
                              imageUrl: v.imageUrl,
                              location: v.location,
                              contact: v.contact,
                              packPrice: double.parse(controller.text.trim()),
                            );
                        ref.invalidate(allVendorsProvider);
                        if (ctx.mounted) Navigator.of(ctx).pop();
                      } catch (e) {
                        setSheet(() => saving = false);
                        if (context.mounted) {
                          _snack(context,
                              'Could not save the pack price. ${AppErrorMapper.map(e)}');
                        }
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    controller.dispose();
  }
}

/// The four sections (always all four, even when empty — each has its own
/// "+ Add"). Pure widget: the tests drive it directly.
class _MenuBody extends StatelessWidget {
  const _MenuBody({
    required this.products,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final List<Product> products;
  final void Function(MenuSection) onAdd;
  final void Function(Product) onEdit;
  final void Function(Product) onDelete;
  final void Function(Product, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final bySection = <MenuSection, List<Product>>{
      for (final s in MenuSection.values) s: [],
    };
    for (final p in products) {
      bySection[MenuSection.of(p)]!.add(p);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        for (final s in MenuSection.values) ...[
          _SectionHeader(section: s, count: bySection[s]!.length, onAdd: onAdd),
          if (bySection[s]!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Nothing here yet.',
                key: ValueKey('empty-${s.name}'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5),
                    ),
              ),
            )
          else
            for (final p in bySection[s]!)
              MenuItemTile(
                key: ValueKey('item-${p.id}'),
                product: p,
                onEdit: () => onEdit(p),
                onDelete: () => onDelete(p),
                onToggle: (v) => onToggle(p, v),
              ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// A fixed-menu vendor's menu: one "+ Add item", then the items grouped by
/// their category (alphabetical, as students see them).
class FixedMenuBody extends StatelessWidget {
  const FixedMenuBody({
    super.key,
    required this.products,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final List<Product> products;
  final VoidCallback onAdd;
  final void Function(Product) onEdit;
  final void Function(Product) onDelete;
  final void Function(Product, bool) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = groupByCategory(products);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Fixed menu (${products.length})',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            AppButton(
              key: const ValueKey('add-fixed-item'),
              label: 'Add item',
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              expand: false,
              icon: AppIcons.add,
              onPressed: onAdd,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Every item is a complete meal with its own price. Students pick '
          'quantities; there are no packs.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        if (products.isEmpty)
          Text('Nothing here yet.',
              key: const ValueKey('empty-fixed'),
              style: theme.textTheme.bodySmall),
        for (final e in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              '${e.key} (${e.value.length})',
              key: ValueKey('category-${e.key}'),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          for (final p in e.value)
            MenuItemTile(
              key: ValueKey('item-${p.id}'),
              product: p,
              onEdit: () => onEdit(p),
              onDelete: () => onDelete(p),
              onToggle: (v) => onToggle(p, v),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.section,
    required this.count,
    required this.onAdd,
  });

  final MenuSection section;
  final int count;
  final void Function(MenuSection) onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${section.label} ($count)',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          AppButton(
            key: ValueKey('add-${section.name}'),
            label: 'Add',
            variant: AppButtonVariant.text,
            size: AppButtonSize.small,
            expand: false,
            icon: AppIcons.add,
            onPressed: () => onAdd(section),
          ),
        ],
      ),
    );
  }
}

/// One menu item row: photo, name, price, availability switch, edit/delete.
class MenuItemTile extends StatelessWidget {
  const MenuItemTile({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Product product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: product.imageUrl != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      child: Image.network(
                        product.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.image_not_supported_outlined,
                          size: 24,
                        ),
                      ),
                    )
                  : const Icon(Icons.fastfood_outlined, size: 24),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.labelLarge),
                  Text(
                    '${Money.format(product.basePrice)}'
                    '${product.isAvailable ? '' : ' · Hidden'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              key: ValueKey('switch-${product.id}'),
              value: product.isAvailable,
              onChanged: onToggle,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove',
                      style: TextStyle(color: context.colors.dangerText)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
