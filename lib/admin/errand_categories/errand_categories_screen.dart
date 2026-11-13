import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/errand_category.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import 'errand_category_form_screen.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/format/money.dart';
import '../../shared/utils/app_error_mapper.dart';

/// Admin management of Errand service categories — add/edit/remove the
/// categories the Student-facing Errand flow reads dynamically.
class ErrandCategoriesScreen extends ConsumerWidget {
  const ErrandCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(adminErrandCategoriesProvider);

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Errand Categories'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add Category'),
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load categories.',
          onRetry: () => ref.invalidate(adminErrandCategoriesProvider),
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
    ErrandCategoryData? category,
  ) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ErrandCategoryFormScreen(category: category),
      ),
    );
  }

  Future<void> _toggleActive(
    WidgetRef ref,
    ErrandCategoryData category,
    bool active,
  ) async {
    await ref.read(adminServiceProvider).upsertErrandCategory(
          id: category.id,
          title: category.title,
          subtitle: category.subtitle,
          description: category.description,
          iconName: category.iconName,
          flatFee: category.flatFee,
          isActive: active,
          sortOrder: category.sortOrder,
        );
    ref.invalidate(adminErrandCategoriesProvider);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ErrandCategoryData category,
  ) async {
    final confirmed = await AppDialog.show(
      context,
      title: 'Delete category?',
      body: 'Remove "${category.title}"? Past requests keep their record — '
          'if any exist for this category, deleting will fail; deactivate '
          'it instead.',
      secondaryLabel: 'Cancel',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (confirmed != true) return;
    try {
      await ref.read(adminServiceProvider).deleteErrandCategory(category.id);
      ref.invalidate(adminErrandCategoriesProvider);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Delete failed — try deactivating instead. (${AppErrorMapper.map(e)})')),
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

  final ErrandCategoryData category;
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
              child: Icon(category.icon,
                  color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.title, style: theme.textTheme.labelLarge),
                  Text(
                    '${category.subtitle} · ${Money.format(category.flatFee)}',
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
              activeThumbColor: context.colors.brand,
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
                  child: Text('Delete',
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
