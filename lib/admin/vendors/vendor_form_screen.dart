import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../services/admin_providers.dart';

/// Form for adding or editing a partner vendor.
/// Returns `true` via `Navigator.pop` on save so the caller can refresh.
class VendorFormScreen extends ConsumerStatefulWidget {
  const VendorFormScreen({super.key, this.vendor});

  /// Null when adding a new vendor.
  final Vendor? vendor;

  @override
  ConsumerState<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends ConsumerState<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _contactCtrl;
  late final TextEditingController _packPriceCtrl;
  late bool _isActive;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final v = widget.vendor;
    _nameCtrl = TextEditingController(text: v?.name ?? '');
    _descCtrl = TextEditingController(text: v?.description ?? '');
    _locationCtrl = TextEditingController(text: v?.location ?? '');
    _contactCtrl = TextEditingController(text: v?.contact ?? '');
    _packPriceCtrl = TextEditingController(
        text: (v?.packPrice ?? 200).toStringAsFixed(0));
    _isActive = v?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _contactCtrl.dispose();
    _packPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      await ref.read(adminServiceProvider).upsertVendor(
            id: widget.vendor?.id,
            name: _nameCtrl.text.trim(),
            description: _descCtrl.text.trim(),
            isActive: _isActive,
            badgeLabel: widget.vendor?.badgeLabel ?? 'Partner',
            imageUrl: widget.vendor?.imageUrl,
            location: _locationCtrl.text.trim().isEmpty
                ? null
                : _locationCtrl.text.trim(),
            contact: _contactCtrl.text.trim().isEmpty
                ? null
                : _contactCtrl.text.trim(),
            packPrice: double.tryParse(_packPriceCtrl.text.trim()) ?? 200,
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
    final isEditing = widget.vendor != null;

    return Scaffold(
      appBar: UniflexAppBar(title: isEditing ? 'Edit Vendor' : 'New Vendor'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Name ─────────────────────────────────────────────────
              AppTextField(
                controller: _nameCtrl,
                hint: 'Vendor name',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Description ──────────────────────────────────────────
              AppTextField(
                controller: _descCtrl,
                hint: 'Short description',
                maxLines: 3,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Location ─────────────────────────────────────────────
              AppTextField(
                controller: _locationCtrl,
                hint: 'Location (e.g. Block A, Ground Floor)',
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Contact ──────────────────────────────────────────────
              AppTextField(
                controller: _contactCtrl,
                hint: 'Contact (phone / WhatsApp)',
                keyboardType: TextInputType.phone,
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Pack price (Section 11) ───────────────────────────────
              AppTextField(
                controller: _packPriceCtrl,
                hint: 'Pack price (₦) — charged per pack at checkout',
                keyboardType: TextInputType.number,
                validator: (v) {
                  final price = double.tryParse(v?.trim() ?? '');
                  if (price == null || price < 0) return 'Enter a valid price';
                  return null;
                },
              ),

              const SizedBox(height: AppSpacing.md),

              // ── Active toggle ─────────────────────────────────────────
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
                              : 'Hidden from student home screen',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
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
                label: isEditing ? 'Save Changes' : 'Add Vendor',
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
