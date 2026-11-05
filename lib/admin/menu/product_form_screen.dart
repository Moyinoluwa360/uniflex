import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/image_upload/image_upload_field.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';

/// Add or edit a menu item. [product] is null when adding a new item.
/// Returns `true` via `Navigator.pop` when the save succeeds so the
/// caller can invalidate its provider.
class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    required this.vendorId,
    this.product,
  });

  final String vendorId;
  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late String _section;
  late String? _foodSubsection;
  late bool _isAvailable;
  String? _imageUrl; // current URL — updated by ImageUploadField
  bool _isSaving = false;

  static const _sections = ['food', 'drinks', 'others'];
  static const _sectionLabels = {'food': 'Food', 'drinks': 'Drinks', 'others': 'Others'};
  static const _foodSubsections = ['meal', 'protein_topping'];
  static const _foodSubsectionLabels = {
    'meal': 'Meals (counts toward pack capacity)',
    'protein_topping': 'Proteins / Toppings (no capacity limit)',
  };

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.basePrice.toStringAsFixed(0) : '');
    _section = p?.section ?? 'food';
    _foodSubsection = p?.foodSubsection ?? (_section == 'food' ? 'meal' : null);
    _isAvailable = p?.isAvailable ?? true;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
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
        category: _sectionLabels[_section] ?? 'Others',
        basePrice: double.parse(_priceCtrl.text.trim()),
        imageUrl: _imageUrl,
        isAvailable: _isAvailable,
        requiresPack: _section == 'food',
        section: _section,
        foodSubsection: _section == 'food' ? _foodSubsection : null,
      );

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

              // ── Section ───────────────────────────────────────────────
              Text('Section', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                value: _section,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 4,
                  ),
                ),
                items: _sections
                    .map((s) => DropdownMenuItem(
                        value: s, child: Text(_sectionLabels[s] ?? s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _section = v;
                      _foodSubsection = v == 'food' ? 'meal' : null;
                    });
                  }
                },
              ),

              // ── Food Subsection (only when section == food) ──────────
              if (_section == 'food') ...[
                const SizedBox(height: AppSpacing.md),
                Text('Food Type', style: theme.textTheme.labelLarge),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  value: _foodSubsection ?? 'meal',
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm + 4,
                    ),
                  ),
                  items: _foodSubsections
                      .map((s) => DropdownMenuItem(
                          value: s,
                          child: Text(_foodSubsectionLabels[s] ?? s)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _foodSubsection = v);
                  },
                ),
              ],

              const SizedBox(height: AppSpacing.md),

              // ── Price ─────────────────────────────────────────────────
              AppTextField(
                controller: _priceCtrl,
                hint: 'Base price (₦)',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a price';
                  final price = double.tryParse(v.trim());
                  if (price == null || price <= 0) {
                    return 'Enter a valid price';
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
                    activeThumbColor: AppColors.emerald,
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),

              PrimaryButton(
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

