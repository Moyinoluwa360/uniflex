import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/image_upload/image_upload_field.dart';
import '../../shared/widgets/inputs/app_form_parts.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../services/admin_providers.dart';
import 'menu_section.dart';

/// Add or edit a menu item. [product] is null when adding a new item.
/// Returns `true` via `Navigator.pop` when the save succeeds so the
/// caller can invalidate its provider.
///
/// When adding, [initialSection] is the section whose "+ Add" was tapped —
/// the item goes straight into it, with no category to pick. When editing,
/// a "Move to" picker is shown so a wrongly-filed item can be corrected.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.vendorId,
    this.product,
    this.initialSection,
    this.fixedMenu = false,
    this.categorySuggestions = const [],
  });

  /// Fixed-menu vendor (Pack 1 / Part 3): asks for a category instead of a
  /// section; no meal / protein / pack fields.
  final bool fixedMenu;

  /// The vendor's existing categories, offered as one-tap chips.
  final List<String> categorySuggestions;

  final String vendorId;
  final Product? product;

  /// The section the new item is added to (ignored when editing — the
  /// item's own section is used).
  final MenuSection? initialSection;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _categoryCtrl;
  late MenuSection _menuSection;
  late bool _isAvailable;
  String? _imageUrl; // current URL — updated by ImageUploadField
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.basePrice.toStringAsFixed(0) : '');
    _categoryCtrl = TextEditingController(
        text: widget.fixedMenu ? (p?.category ?? '') : '');
    _menuSection = p != null
        ? MenuSection.of(p)
        : (widget.initialSection ?? MenuSection.meals);
    _isAvailable = p?.isAvailable ?? true;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(adminServiceProvider).upsertProduct(
            id: widget.product?.id,
            vendorId: widget.vendorId,
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            // Pack-based: `category` is the legacy free-text column; keep it
            // readable. Fixed menu: it IS the grouping students see.
            category: widget.fixedMenu
                ? _categoryCtrl.text.trim()
                : _menuSection.label,
            basePrice: double.parse(_priceCtrl.text.trim()),
            imageUrl: _imageUrl,
            isAvailable: _isAvailable,
            // Fixed menu: a plain priced item (the server stores it the same
            // way whatever is sent).
            requiresPack: widget.fixedMenu ? false : _menuSection.requiresPack,
            section: widget.fixedMenu ? 'food' : _menuSection.section,
            foodSubsection:
                widget.fixedMenu ? 'meal' : _menuSection.foodSubsection,
          );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save the item. ${AppErrorMapper.map(e)}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.product != null;

    return Scaffold(
      appBar: UniflexAppBar(
        title: isEditing ? 'Edit Item' : 'New Item',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Image ────────────────────────────────────────────────
              Text('Photo', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              ImageUploadField(
                initialUrl: _imageUrl,
                cropToSquare: true,
                hint: 'Photos are cropped to a square.',
                uploadFn: ref.read(adminServiceProvider).uploadProductImage,
                onChanged: (url) => setState(() => _imageUrl = url),
              ),

              const SizedBox(height: AppSpacing.lg),

              // ── Name ─────────────────────────────────────────────────
              AppTextField(
                key: const ValueKey('form-name'),
                controller: _nameCtrl,
                hint: 'Item name',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Description ──────────────────────────────────────────
              AppTextField(
                controller: _descCtrl,
                hint: 'Description (optional)',
                maxLines: 3,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Category (fixed menu) ─────────────────────────────────
              if (widget.fixedMenu) ...[
                AppTextField(
                  key: const ValueKey('form-category'),
                  controller: _categoryCtrl,
                  hint: 'Category (e.g. Rice, Swallow, Drinks)',
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'Enter a category';
                    if (t.length > 40) return 'Keep it under 40 characters';
                    return null;
                  },
                ),
                if (widget.categorySuggestions.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final cat in widget.categorySuggestions)
                        AppChoiceChip(
                          label: cat,
                          selected: _categoryCtrl.text.trim() == cat,
                          onTap: () => setState(() => _categoryCtrl.text = cat),
                        ),
                    ],
                  ),
                ],
              ]
              // ── Section ───────────────────────────────────────────────
              // Adding: fixed to the section whose "+ Add" was tapped.
              // Editing: a picker, so a wrongly-filed item can be moved.
              else if (!isEditing)
                Container(
                  key: const ValueKey('form-section-label'),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    'Adding to ${_menuSection.label}',
                    style: theme.textTheme.labelLarge,
                  ),
                )
              else ...[
                Text('Section', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<MenuSection>(
                  key: const ValueKey('form-section-picker'),
                  initialValue: _menuSection,
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
                    for (final s in MenuSection.values)
                      DropdownMenuItem(value: s, child: Text(s.label)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _menuSection = v);
                  },
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // ── Price ─────────────────────────────────────────────────
              AppTextField(
                key: const ValueKey('form-price'),
                controller: _priceCtrl,
                hint: widget.fixedMenu
                    ? 'Price per portion (₦)'
                    : 'Base price (₦)',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a price';
                  final price = double.tryParse(v.trim());
                  if (price == null || price <= 0) {
                    return 'Enter a valid price';
                  }
                  if (widget.fixedMenu && price > 500000) {
                    return 'Price must be ₦500,000 or less';
                  }
                  return null;
                },
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Availability toggle ───────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Available', style: theme.textTheme.labelLarge),
                        Text(
                          _isAvailable
                              ? 'Visible to students'
                              : 'Hidden from students (sold out)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isAvailable,
                    onChanged: (v) => setState(() => _isAvailable = v),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),

              AppButton(
                label: isEditing ? 'Save Changes' : 'Add Item',
                icon: Icons.check,
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
