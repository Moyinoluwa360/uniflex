import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../services/admin_providers.dart';
import 'product_form_screen.dart';

/// Uniflex's own menu — all products for the internal Uniflex vendor
/// (vendor ID `00000000-0000-0000-0000-000000000001`).
///
/// Admin can add, edit, delete, and toggle availability. Changes here
/// immediately reflect in the student-facing catalog (the student's
/// vendorProductsProvider filters by is_available = true; toggling
/// availability shows/hides items in real time once the provider is
/// refreshed).
class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({super.key});

  // Fixed UUID seeded in Phase 2 — the Uniflex vendor ID.
  static const _uniflexVendorId = '00000000-0000-0000-0000-000000000001';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final productsAsync =
        ref.watch(adminVendorProductsProvider(_uniflexVendorId));

    return Scaffold(
      appBar: AppBar(title: const Text('Menu Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load menu',
              style: theme.textTheme.bodyMedium),
        ),
        data: (products) {
          if (products.isEmpty) {
            return const Center(
              child: Text('No items yet. Tap + to add one.'),
            );
          }

          // Group by category
          final byCategory = <String, List<Product>>{};
          for (final p in products) {
            byCategory.putIfAbsent(p.category, () => []).add(p);
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72, // space for FAB
            ),
            itemCount: byCategory.length,
            itemBuilder: (context, i) {
              final category = byCategory.keys.elementAt(i);
              final items = byCategory[category]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (i > 0) const SizedBox(height: AppSpacing.lg),
                  Text(category, style: theme.textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  ...items.map(
                    (p) => _ProductTile(
                      product: p,
                      vendorId: _uniflexVendorId,
                      onEdit: () => _openForm(context, ref, p),
                      onDelete: () => _confirmDelete(context, ref, p),
                      onToggle: (available) => _toggleAvailability(
                          ref, p, available),
                    ),
                  ),
                ],
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
        builder: (_) => ProductFormScreen(
          vendorId: _uniflexVendorId,
          product: product,
        ),
      ),
    );
    if (saved == true) {
      ref.invalidate(adminVendorProductsProvider(_uniflexVendorId));
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
        content: Text('Remove "${product.name}" from the menu? This cannot be undone.'),
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
      await ref
          .read(adminServiceProvider)
          .deleteProduct(product.id);
      ref.invalidate(adminVendorProductsProvider(_uniflexVendorId));
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
        );
    ref.invalidate(adminVendorProductsProvider(_uniflexVendorId));
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.vendorId,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final Product product;
  final String vendorId;
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
            // Image or placeholder
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
                    '₦${product.basePrice.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            // Availability toggle
            Switch(
              value: product.isAvailable,
              onChanged: onToggle,
              activeThumbColor: AppColors.emerald,
            ),
            // More options
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: AppColors.error)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
