import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/around_category.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';

/// Add or edit an Around category (post-testing fixes, Section 9).
/// [category] is null when adding a new one. Returns `true` via
/// `Navigator.pop` on save so the caller can refresh.
class AroundCategoryFormScreen extends ConsumerStatefulWidget {
  const AroundCategoryFormScreen({super.key, this.category});

  final AroundCategoryData? category;

  @override
  ConsumerState<AroundCategoryFormScreen> createState() =>
      _AroundCategoryFormScreenState();
}

class _AroundCategoryFormScreenState
    extends ConsumerState<AroundCategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _feeCtrl;
  late final TextEditingController _sortOrderCtrl;
  late String _iconName;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _titleCtrl = TextEditingController(text: c?.title ?? '');
    _subtitleCtrl = TextEditingController(text: c?.subtitle ?? '');
    _descriptionCtrl = TextEditingController(text: c?.description ?? '');
    _feeCtrl = TextEditingController(text: c != null ? c.flatFee.toStringAsFixed(0) : '');
    _sortOrderCtrl = TextEditingController(text: '${c?.sortOrder ?? 0}');
    _iconName = c?.iconName ?? AroundCategoryData.availableIconNames.first;
    _isActive = c?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _descriptionCtrl.dispose();
    _feeCtrl.dispose();
    _sortOrderCtrl.dispose();
    super.dispose();
  }

  /// Slugifies the title into a stable `key` for a brand-new category —
  /// existing categories never change their key (around_requests
  /// reference it via foreign key).
  String _slugify(String title) {
    final base = title
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'category_${DateTime.now().millisecondsSinceEpoch}' : base;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(adminServiceProvider).upsertAroundCategory(
            id: widget.category?.id,
            key: widget.category?.key ?? _slugify(_titleCtrl.text.trim()),
            title: _titleCtrl.text.trim(),
            subtitle: _subtitleCtrl.text.trim(),
            description: _descriptionCtrl.text.trim(),
            iconName: _iconName,
            flatFee: double.parse(_feeCtrl.text.trim()),
            isActive: _isActive,
            sortOrder: int.tryParse(_sortOrderCtrl.text.trim()) ?? 0,
          );
      ref.invalidate(adminAroundCategoriesProvider);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.category != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Edit Category' : 'New Category')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _titleCtrl,
                hint: 'Title (e.g. Laundry Pickup & Dropoff)',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a title' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _subtitleCtrl,
                hint: 'Short subtitle shown on the card',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a subtitle' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _descriptionCtrl,
                hint: 'Full description shown on the request screen',
                maxLines: 3,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Icon', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _iconName,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 4,
                  ),
                ),
                items: [
                  for (final name in AroundCategoryData.availableIconNames)
                    DropdownMenuItem(
                      value: name,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(AroundCategoryData.iconFor(name), size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          Text(name),
                        ],
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _iconName = v);
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _feeCtrl,
                hint: 'Flat fee (₦)',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final fee = double.tryParse(v?.trim() ?? '');
                  if (fee == null || fee < 0) return 'Enter a valid fee';
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _sortOrderCtrl,
                hint: 'Sort order (lower shows first)',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Active', style: theme.textTheme.labelLarge),
                        Text(
                          _isActive
                              ? 'Visible to students'
                              : 'Hidden from the student Around tab',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    activeThumbColor: AppColors.emerald,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              PrimaryButton(
                label: isEditing ? 'Save Changes' : 'Add Category',
                isLoading: _isSaving,
                onPressed: _save,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}
