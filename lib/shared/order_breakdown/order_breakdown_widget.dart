import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../widgets/accordions/app_accordion_card.dart';
import '../widgets/async/retry_section.dart';
import 'order_breakdown_models.dart';
import 'order_breakdown_provider.dart';

/// THE order breakdown (Pack 4B). One widget, used by the rider pool
/// preview, the rider's active job, Admin order details and the student's
/// order tracking, so all four always show the same thing.
///
/// Layout:
///  * single vendor — vendor name + location as a plain header, then each
///    pack as its own CLOSED dropdown ("Pack 1 · ₦200"), then plain Drinks /
///    Others lists (only when present). No packs ⇒ no pack section.
///  * multi vendor — each vendor is a CLOSED dropdown; opening it shows the
///    same layout. Nothing opens by itself.
///
/// Never shows delivery / commitment / service fees: the data simply does
/// not contain them.
///
/// `showPrices: false` is the "no prices" mode a gift recipient gets: pack
/// titles drop their price, and vendor totals / line amounts are hidden.
class OrderBreakdown extends ConsumerWidget {
  const OrderBreakdown(
      {super.key, required this.orderId, this.showPrices = true});

  final bool showPrices;

  /// A delivery-group id, or a standalone (pickup) order id.
  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderBreakdownProvider(orderId));
    return async.when(
      loading: () => const _BreakdownShimmer(),
      error: (e, _) => RetrySection(
        message: 'Could not load item details.',
        compact: true,
        onRetry: () => ref.invalidate(orderBreakdownProvider(orderId)),
      ),
      data: (data) => OrderBreakdownView(data: data, showPrices: showPrices),
    );
  }
}

/// Pure rendering of an already-loaded [OrderBreakdownData] (also what the
/// widget tests drive directly).
class OrderBreakdownView extends StatefulWidget {
  const OrderBreakdownView(
      {super.key, required this.data, this.showPrices = true});

  final OrderBreakdownData data;

  /// False ⇒ no amount of any kind is drawn (gift recipient view).
  final bool showPrices;

  @override
  State<OrderBreakdownView> createState() => _OrderBreakdownViewState();
}

class _OrderBreakdownViewState extends State<OrderBreakdownView> {
  // Everything starts closed; only what the user taps opens.
  final Set<String> _open = {};

  void _toggle(String key) => setState(() {
        if (!_open.remove(key)) _open.add(key);
      });

  @override
  Widget build(BuildContext context) {
    final vendors = widget.data.vendors;
    final theme = Theme.of(context);

    if (vendors.isEmpty) {
      return Text(
        'No items',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    if (vendors.length == 1) {
      return _VendorBody(
        vendor: vendors.first,
        vendorKey: 'v0',
        showHeader: true,
        showPrices: widget.showPrices,
        open: _open,
        onToggle: _toggle,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < vendors.length; i++)
          AppAccordionCard(
            key: ValueKey('vendor-card-$i'),
            outerPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            leading: buildAccordionLeadingIcon(
              context: context,
              icon: Icons.storefront_outlined,
              color: AppColors.emerald,
            ),
            title: vendors[i].vendorName,
            subtitle: '${vendors[i].itemCount} item'
                '${vendors[i].itemCount == 1 ? '' : 's'}'
                '${widget.showPrices ? ' · ₦${vendors[i].vendorTotal.toStringAsFixed(0)}' : ''}',
            isExpanded: _open.contains('v$i'),
            onTap: () => _toggle('v$i'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
              child: _VendorBody(
                vendor: vendors[i],
                vendorKey: 'v$i',
                showHeader: false,
                showPrices: widget.showPrices,
                open: _open,
                onToggle: _toggle,
              ),
            ),
          ),
      ],
    );
  }
}

class _VendorBody extends StatelessWidget {
  const _VendorBody({
    required this.vendor,
    required this.vendorKey,
    required this.showHeader,
    required this.showPrices,
    required this.open,
    required this.onToggle,
  });

  final VendorBreakdown vendor;
  final String vendorKey;
  final bool showHeader;
  final bool showPrices;
  final Set<String> open;
  final void Function(String) onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final children = <Widget>[];

    if (showHeader) {
      children.add(Row(
        children: [
          const Icon(Icons.storefront_outlined,
              size: 18, color: AppColors.emerald),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              vendor.vendorName,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ));
      if (vendor.vendorLocation != null &&
          vendor.vendorLocation!.trim().isNotEmpty) {
        children.add(Padding(
          padding: const EdgeInsets.only(left: 26, top: 2),
          child: Text(
            vendor.vendorLocation!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ));
      }
      children.add(const SizedBox(height: AppSpacing.sm));
    }

    // Packs — each its own closed dropdown. No packs ⇒ nothing here.
    for (final pack in vendor.packs) {
      final key = '$vendorKey-p${pack.index}';
      final n = pack.items.length;
      children.add(AppAccordionCard(
        key: ValueKey('pack-card-$key'),
        outerPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        leading: buildAccordionLeadingIcon(
          context: context,
          icon: Icons.inventory_2_outlined,
          color: AppColors.orange,
        ),
        title: showPrices ? pack.title : pack.titleNoPrice,
        subtitle: '$n item${n == 1 ? '' : 's'}',
        isExpanded: open.contains(key),
        onTap: () => onToggle(key),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
          child: Column(
            children: [
              for (final line in pack.items)
                _LineRow(name: line.name, quantity: line.quantity),
            ],
          ),
        ),
      ));
    }

    // Plain lists — only when the vendor actually has such items.
    if (vendor.items.isNotEmpty) {
      children.add(_PlainList(
          title: 'Items', lines: vendor.items, showPrices: showPrices));
    }
    if (vendor.drinks.isNotEmpty) {
      children.add(_PlainList(
          title: 'Drinks', lines: vendor.drinks, showPrices: showPrices));
    }
    if (vendor.others.isNotEmpty) {
      children.add(_PlainList(
          title: 'Others', lines: vendor.others, showPrices: showPrices));
    }

    if (vendor.isEmpty) {
      children.add(Text(
        'No items',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ));
    } else if (showPrices) {
      children.add(const SizedBox(height: AppSpacing.sm));
      children.add(Row(
        children: [
          Expanded(
            child: Text('Vendor total', style: theme.textTheme.labelMedium),
          ),
          Text(
            '₦${vendor.vendorTotal.toStringAsFixed(0)}',
            key: ValueKey('vendor-total-$vendorKey'),
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _PlainList extends StatelessWidget {
  const _PlainList(
      {required this.title, required this.lines, required this.showPrices});

  final String title;
  final List<BreakdownLine> lines;
  final bool showPrices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding:
              const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
          child: Text(
            title,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        for (final l in lines)
          _LineRow(
              name: l.name,
              quantity: l.quantity,
              amount: showPrices ? l.lineTotal : null),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.name, required this.quantity, this.amount});

  final String name;
  final int quantity;
  final double? amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text('$quantity× $name', style: theme.textTheme.bodyMedium),
          ),
          if (amount != null)
            Text(
              '₦${amount!.toStringAsFixed(0)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownShimmer extends StatelessWidget {
  const _BreakdownShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: List.generate(
        2,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }
}
