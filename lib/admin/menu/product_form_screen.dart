import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/models/product.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
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
  late String _category;
  late bool _isAvailable;
  late bool _requiresPack;
  String? _imageUrl; // existing URL (from product being edited)
  Uint8List? _pickedBytes; // newly picked image bytes
  String? _pickedFileName;
  bool _isSaving = false;

  static const _categories = [
    'Protein Meals',
    'Sides',
    'Snacks',
    'Drinks',
    'Main',
    'Grills',
    'Smoothies',
    'Juices',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl = TextEditingController(
        text: p != null ? p.basePrice.toStringAsFixed(0) : '');
    _category = p?.category ?? _categories.first;
    _isAvailable = p?.isAvailable ?? true;
    _requiresPack = p?.requiresPack ?? false;
    _imageUrl = p?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedBytes = bytes;
      _pickedFileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final service = ref.read(adminServiceProvider);

      // Upload new image if one was picked.
      String? imageUrl = _imageUrl;
      if (_pickedBytes != null && _pickedFileName != null) {
        imageUrl = await service.uploadProductImage(
          _pickedBytes!,
          _pickedFileName!,
        );
      }

      await service.upsertProduct(
        id: widget.product?.id,
        vendorId: widget.vendorId,
        name: _nameCtrl.text.trim(),
        description: _descCtrl.text.trim(),
        category: _category,
        basePrice: double.parse(_priceCtrl.text.trim()),
        imageUrl: imageUrl,
        isAvailable: _isAvailable,
        requiresPack: _requiresPack,
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
              _ImagePicker(
                existingUrl: _imageUrl,
                pickedBytes: _pickedBytes,
                onTap: _pickImage,
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

              // ── Category ─────────────────────────────────────────────
              Text('Category', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 4,
                  ),
                ),
                items: _categories
                    .map((c) =>
                        DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),

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

              const SizedBox(height: AppSpacing.md),

              // ── Requires Pack toggle (Section 11) ─────────────────────
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Requires Pack', style: theme.textTheme.labelLarge),
                        Text(
                          'On for food that needs a container to hand over '
                          '(off for drinks, etc.)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _requiresPack,
                    onChanged: (v) => setState(() => _requiresPack = v),
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

class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.existingUrl,
    required this.pickedBytes,
    required this.onTap,
  });

  final String? existingUrl;
  final Uint8List? pickedBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget child;

    if (pickedBytes != null) {
      child = Image.memory(pickedBytes!, fit: BoxFit.cover);
    } else if (existingUrl != null) {
      child = Image.network(
        existingUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.image_not_supported_outlined,
          size: 32,
        ),
      );
    } else {
      child = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate_outlined,
            size: 32,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to add photo',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 140,
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: theme.dividerColor,
            style: BorderStyle.solid,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
