import 'package:flutter/material.dart';

import '../../shared/models/cart_item.dart';
import '../../shared/models/vendor.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';

/// One pack the student has built: how many of each pack-requiring
/// product go into it.
class PackAllocation {
  const PackAllocation(this.items);

  /// productId -> quantity in this pack.
  final Map<String, int> items;

  Map<String, dynamic> toJson(Map<String, CartItem> itemsByProductId) {
    return {
      'items': items.entries
          .map((e) => {
                'product_id': e.key,
                'product_name': itemsByProductId[e.key]?.product.name ?? '',
                'quantity': e.value,
              })
          .toList(),
    };
  }
}

/// Post-testing fixes, Section 11 — pack allocation. Shown at checkout
/// when the cart contains any pack-requiring items and the student says
/// "Yes" to using packs. A single pack can mix different pack-requiring
/// items together; the student repeats "Add another pack" until every
/// pack-requiring unit is allocated, then "Done".
///
/// Returns the finished `List<PackAllocation>` via `Navigator.pop`, or
/// `null` if the student backs out.
class PackAllocationScreen extends StatefulWidget {
  const PackAllocationScreen({
    super.key,
    required this.vendor,
    required this.packableItems,
  });

  final Vendor vendor;

  /// Cart items whose product.requiresPack is true. Non-pack items
  /// (drinks, etc.) never appear here — they're added to the order as
  /// normal, no pack step involved.
  final List<CartItem> packableItems;

  @override
  State<PackAllocationScreen> createState() => _PackAllocationScreenState();
}

class _PackAllocationScreenState extends State<PackAllocationScreen> {
  late final Map<String, CartItem> _itemsByProductId;
  late Map<String, int> _remaining;
  final _packs = <PackAllocation>[];
  late Map<String, int> _currentSelection;

  @override
  void initState() {
    super.initState();
    _itemsByProductId = {
      for (final item in widget.packableItems) item.product.id: item,
    };
    _remaining = {
      for (final item in widget.packableItems) item.product.id: item.quantity,
    };
    _currentSelection = {for (final id in _remaining.keys) id: 0};
  }

  int get _totalRemaining => _remaining.values.fold(0, (a, b) => a + b);
  int get _currentSelectedCount =>
      _currentSelection.values.fold(0, (a, b) => a + b);

  void _addPack() {
    final chosen = Map<String, int>.fromEntries(
      _currentSelection.entries.where((e) => e.value > 0),
    );
    if (chosen.isEmpty) return;
    setState(() {
      _packs.add(PackAllocation(chosen));
      for (final entry in chosen.entries) {
        _remaining[entry.key] = (_remaining[entry.key] ?? 0) - entry.value;
      }
      _currentSelection = {for (final id in _remaining.keys) id: 0};
    });
  }

  void _removePack(int index) {
    setState(() {
      final removed = _packs.removeAt(index);
      for (final entry in removed.items.entries) {
        _remaining[entry.key] = (_remaining[entry.key] ?? 0) + entry.value;
      }
    });
  }

  void _done() {
    Navigator.of(context).pop(_packs);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allAllocated = _totalRemaining == 0;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Build Pack ${_packs.length + 1}',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Choose what goes into this pack. Mix items freely — '
                      'one pack costs ₦${widget.vendor.packPrice.toStringAsFixed(0)}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            if (allAllocated) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, color: AppColors.emerald),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Everything is packed. Tap Done to continue.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: AppColors.emerald),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text('Remaining to pack', style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ..._remaining.entries.where((e) => e.value > 0).map((entry) {
                final item = _itemsByProductId[entry.key]!;
                final selected = _currentSelection[entry.key] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.name, style: theme.textTheme.bodyMedium),
                            Text(
                              '${entry.value} left unpacked',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: selected > 0
                            ? () => setState(() =>
                                _currentSelection[entry.key] = selected - 1)
                            : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      SizedBox(
                        width: 24,
                        child: Text('$selected',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall),
                      ),
                      IconButton(
                        onPressed: selected < entry.value
                            ? () => setState(() =>
                                _currentSelection[entry.key] = selected + 1)
                            : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _currentSelectedCount > 0 ? _addPack : null,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: Text('Add Pack ${_packs.length + 1}'),
              ),
            ],

            if (_packs.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xl),
              Text('Packs built (${_packs.length})',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              ..._packs.asMap().entries.map((entry) {
                final i = entry.key;
                final pack = entry.value;
                final summary = pack.items.entries
                    .map((e) => '${e.value}× ${_itemsByProductId[e.key]?.product.name}')
                    .join(', ');
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('Pack ${i + 1}: $summary',
                            style: theme.textTheme.bodySmall),
                      ),
                      IconButton(
                        onPressed: () => _removePack(i),
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Remove pack',
                      ),
                    ],
                  ),
                );
              }),
            ],

            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.sm,
            AppSpacing.screenGutter,
            AppSpacing.md,
          ),
          child: PrimaryButton(
            label: allAllocated
                ? 'Done — ${_packs.length} pack${_packs.length == 1 ? '' : 's'}'
                : 'Pack everything to continue',
            onPressed: allAllocated ? _done : null,
          ),
        ),
      ),
    );
  }
}
