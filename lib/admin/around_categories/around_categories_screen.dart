import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/around_category.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import 'around_category_form_screen.dart';

/// Admin management of Around service categories (post-testing fixes,
/// Section 9) — add/edit/remove the categories the Student-facing Around
/// flow reads dynamically, instead of a hardcoded set.
class AroundCategoriesScreen extends ConsumerWidget {
  const AroundCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(adminAroundCategoriesProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Around Categories'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load categories.',
          onRetry: () => ref.invalidate(adminAroundCategoriesProvider),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(
              child: Text('No categories yet. Tap + to add one.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.md,
              AppSpacing.screenGutter,
              AppSpacing.xl + 72,
            ),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final category = categories[i];
              return _CategoryCard(
                category: category,
                onEdit: () => _openForm(context, ref, category),
                onDelete: () => _confirmDelete(context, ref, category),
                onToggle: (active) => _toggleActive(ref, category, active),
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
    AroundCategoryData? category,
  ) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AroundCategoryFormScreen(category: category),
      ),
    );
  }

  Future<void> _toggleActive(
    WidgetRef ref,
    AroundCategoryData category,
    bool active,
  ) async {
    await ref.read(adminServiceProvider).upsertAroundCategory(
          id: category.id,
          title: category.title,
          subtitle: category.subtitle,
          description: category.description,
          iconName: category.iconName,
          flatFee: category.flatFee,
          isActive: active,
          sortOrder: category.sortOrder,
        );
    ref.invalidate(adminAroundCategoriesProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AroundCategoryData category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Remove "${category.title}"? Past requests keep their record — '
          'if any exist for this category, deleting will fail; deactivate '
          'it instead.',
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
      await ref.read(adminServiceProvider).deleteAroundCategory(category.id);
      ref.invalidate(adminAroundCategoriesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed — try deactivating instead. ($e)')),
        );
      }
    }
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  final AroundCategoryData category;
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
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.control - 4),
              ),
              child: Icon(category.icon, color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.title, style: theme.textTheme.labelLarge),
                  Text(
                    '${category.subtitle} · ₦${category.flatFee.toStringAsFixed(0)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: category.isActive,
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
