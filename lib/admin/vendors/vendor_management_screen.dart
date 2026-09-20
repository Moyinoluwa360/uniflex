import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../services/admin_providers.dart';
import 'vendor_form_screen.dart';
import 'vendor_products_screen.dart';

/// Manage partner vendors: list all vendors, add/edit, and manage each
/// vendor's product menu. The Uniflex vendor itself is excluded — its menu
/// is managed separately via [MenuManagementScreen].
class VendorManagementScreen extends ConsumerWidget {
  const VendorManagementScreen({super.key});

  // Uniflex vendor ID — excluded from partner management.
  static const _uniflexId = '00000000-0000-0000-0000-000000000001';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final vendorsAsync = ref.watch(allVendorsProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Vendors'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Vendor'),
      ),
      body: vendorsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load vendors',
              style: theme.textTheme.bodyMedium),
        ),
        data: (vendors) {
          final partners =
              vendors.where((v) => v.id != _uniflexId).toList();

          if (partners.isEmpty) {
            return const Center(
              child: Text('No partner vendors yet. Tap + to add one.'),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            itemCount: partners.length,
            itemBuilder: (context, i) {
              return _VendorCard(
                vendor: partners[i],
                onEdit: () => _openForm(context, ref, partners[i]),
                onManageMenu: () => _openMenu(context, ref, partners[i]),
                onDelete: () => _confirmDelete(context, ref, partners[i]),
                onToggle: (active) =>
                    _toggleActive(ref, partners[i], active),
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
    Vendor? vendor,
  ) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VendorFormScreen(vendor: vendor),
      ),
    );
    if (saved == true) ref.invalidate(allVendorsProvider);
  }

  void _openMenu(BuildContext context, WidgetRef ref, Vendor vendor) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VendorProductsScreen(vendor: vendor),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Vendor vendor,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete vendor?'),
        content: Text(
          'Remove "${vendor.name}"? This will also delete all their products.',
        ),
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
      await ref.read(adminServiceProvider).deleteVendor(vendor.id);
      ref.invalidate(allVendorsProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _toggleActive(
    WidgetRef ref,
    Vendor vendor,
    bool active,
  ) async {
    await ref.read(adminServiceProvider).upsertVendor(
          id: vendor.id,
          name: vendor.name,
          description: vendor.description,
          isActive: active,
          badgeLabel: vendor.badgeLabel,
          imageUrl: vendor.imageUrl,
          location: vendor.location,
          contact: vendor.contact,
        );
    ref.invalidate(allVendorsProvider);
  }
}

class _VendorCard extends StatelessWidget {
  const _VendorCard({
    required this.vendor,
    required this.onEdit,
    required this.onManageMenu,
    required this.onDelete,
    required this.onToggle,
  });

  final Vendor vendor;
  final VoidCallback onEdit;
  final VoidCallback onManageMenu;
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Logo / placeholder
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: vendor.imageUrl != null
                      ? ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                          child: Image.network(vendor.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const Icon(Icons.storefront_outlined)),
                        )
                      : const Icon(Icons.storefront_outlined),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(vendor.name, style: theme.textTheme.titleSmall),
                      if (vendor.location != null)
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 12,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                vendor.location!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Active toggle
                Switch(
                  value: vendor.isActive,
                  onChanged: onToggle,
                  activeThumbColor: AppColors.emerald,
                ),
                // More options
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'edit') onEdit();
                    if (v == 'menu') onManageMenu();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(
                        value: 'menu', child: Text('Manage Menu')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: AppColors.error)),
                    ),
                  ],
                ),
              ],
            ),
            if (vendor.description.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                vendor.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (vendor.contact != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.phone_outlined,
                    size: 12,
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    vendor.contact!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: onManageMenu,
              icon: const Icon(Icons.menu_book_outlined, size: 16),
              label: const Text('Manage Menu'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs + 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
