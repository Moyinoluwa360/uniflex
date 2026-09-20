import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../menu/product_form_screen.dart';
import '../services/admin_providers.dart';

/// Manage a partner vendor's product catalog — same interactions as
/// [MenuManagementScreen] but scoped to the given [vendor].
class VendorProductsScreen extends ConsumerWidget {
  const VendorProductsScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync =
        ref.watch(adminVendorProductsProvider(vendor.id));

    return Scaffold(
      appBar: UniflexAppBar(title: '${vendor.name} — Menu'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load menu', style: theme.textTheme.bodyMedium),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const Center(
              child: Text('No items yet. Tap + to add one.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            itemCount: products.length,
            itemBuilder: (context, i) {
              return _PartnerProductTile(
                product: products[i],
                onEdit: () => _openForm(context, ref, products[i]),
                onDelete: () => _confirmDelete(context, ref, products[i]),
                onToggle: (v) =>
                    _toggleAvailability(ref, products[i], v),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref,
    Product? product,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProductFormScreen(vendorId: vendor.id, product: product),
      ),
    );
    if (saved == true) {
      ref.invalidate(adminVendorProductsProvider(vendor.id));
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('Remove "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteProduct(product.id);
      ref.invalidate(adminVendorProductsProvider(vendor.id));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleAvailability(
    WidgetRef ref,
    Product product,
    bool available,
  ) async {
    await ref.read(adminServiceProvider).upsertProduct(
          id: product.id,
          vendorId: product.vendorId,
          name: product.name,
          description: product.description,
          category: product.category,
          basePrice: product.basePrice,
          imageUrl: product.imageUrl,
          isAvailable: available,
          requiresPack: product.requiresPack,
        );
    ref.invalidate(adminVendorProductsProvider(vendor.id));
  }
}

class _PartnerProductTile extends StatelessWidget {
  const _PartnerProductTile({
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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: product.imageUrl != null
                  ? ClipRRect(
                      borderRadius:
                          BorderRadius.circular(AppRadius.control),
                      child: Image.network(product.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.fastfood_outlined, size: 22)))
                  : const Icon(Icons.fastfood_outlined, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name, style: theme.textTheme.labelLarge),
                  Text(
                    '${product.category} · ₦${product.basePrice.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: product.isAvailable,
              onChanged: onToggle,
              activeThumbColor: AppColors.emerald,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete',
                      style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
