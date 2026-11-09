import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_location.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../student/ordering/order_repository.dart';

/// Admin provider for ALL delivery locations (including inactive ones).
final adminDeliveryLocationsProvider =
    FutureProvider<List<DeliveryLocation>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('delivery_locations')
      .select()
      .order('sort_order')
      .order('name');
  return rows.map((m) => DeliveryLocation.fromMap(m)).toList();
});

/// Admin screen for managing named delivery locations with prices.
/// Replaces the old campus/hostel fee key-value screen (Round 7).
class DeliverySettingsScreen extends ConsumerWidget {
  const DeliverySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final locsAsync = ref.watch(adminDeliveryLocationsProvider);

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Delivery Locations',
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add location',
            onPressed: () => _openForm(context, ref, null),
          ),
        ],
      ),
      body: locsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (locs) {
          if (locs.isEmpty) {
            return Center(
              child: Text(
                'No delivery locations yet.',
                style: theme.textTheme.bodyMedium,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: locs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final loc = locs[i];
              return _LocationTile(
                location: loc,
                onEdit: () => _openForm(context, ref, loc),
                onDelete: () => _confirmDelete(context, ref, loc),
              );
            },
          );
        },
      ),
    );
  }

  void _openForm(
      BuildContext context, WidgetRef ref, DeliveryLocation? existing) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DeliveryLocationFormScreen(existing: existing),
    ));
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, DeliveryLocation loc) async {
    final confirmed = await AppDialog.show(
context,
title: 'Delete location?',
body: 'Remove "${loc.name}"? This cannot be undone.',
secondaryLabel: 'Cancel',
confirmLabel: 'Delete',
destructive: true,
);

    if (confirmed != true) return;

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('delete_delivery_location', params: {'p_id': loc.id});
      ref.invalidate(adminDeliveryLocationsProvider);
      ref.invalidate(deliveryLocationsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location deleted.'),
              behavior: SnackBarBehavior.floating),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({
    required this.location,
    required this.onEdit,
    required this.onDelete,
  });

  final DeliveryLocation location;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(location.name, style: theme.textTheme.labelLarge),
                    if (!location.isActive) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.colors.surfaceRaised,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          'Hidden',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: context.colors.dangerText),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '₦${location.price.toStringAsFixed(0)} base fee',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
            tooltip: 'Edit',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 20, color: context.colors.dangerText),
            onPressed: onDelete,
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}

// ── Form screen for adding / editing a delivery location ──────────────────

class _DeliveryLocationFormScreen extends ConsumerStatefulWidget {
  const _DeliveryLocationFormScreen({this.existing});

  final DeliveryLocation? existing;

  @override
  ConsumerState<_DeliveryLocationFormScreen> createState() =>
      _DeliveryLocationFormScreenState();
}

class _DeliveryLocationFormScreenState
    extends ConsumerState<_DeliveryLocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _sortController = TextEditingController();
  bool _isActive = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameController.text = widget.existing!.name;
      _priceController.text = widget.existing!.price.toStringAsFixed(0);
      _sortController.text = widget.existing!.sortOrder.toString();
      _isActive = widget.existing!.isActive;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _sortController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc('upsert_delivery_location', params: {
        if (widget.existing != null) 'p_id': widget.existing!.id,
        'p_name': _nameController.text.trim(),
        'p_price': double.parse(_priceController.text.trim()),
        'p_is_active': _isActive,
        'p_sort_order': int.tryParse(_sortController.text.trim()) ?? 0,
      });

      ref.invalidate(adminDeliveryLocationsProvider);
      ref.invalidate(deliveryLocationsProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.existing != null
                ? 'Location updated.'
                : 'Location added.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;

    return Scaffold(
      appBar:
          UniflexAppBar(title: isEditing ? 'Edit Location' : 'Add Location'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(
                controller: _nameController,
                label: 'Location name',
                hint: 'e.g. Engineering Hostel',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _priceController,
                label: 'Base price (₦)',
                hint: '300',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (double.tryParse(v.trim()) == null) {
                    return 'Invalid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              AppTextField(
                controller: _sortController,
                label: 'Sort order',
                hint: '0',
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),
              SwitchListTile(
                title: const Text('Active'),
                subtitle:
                    const Text('Hidden locations are not shown to students.'),
                value: _isActive,
                onChanged: (v) => setState(() => _isActive = v),
              ),
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: isEditing ? 'Save Changes' : 'Add Location',
                icon: Icons.save_outlined,
                isLoading: _isSaving,
                onPressed: _isSaving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
