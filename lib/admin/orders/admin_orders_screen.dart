import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../kitchen/kitchen_queue_screen.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';
import '../../shared/services/auth/auth_providers.dart';

/// Tabbed order management screen for super_admin: Food | Deliveries | Errands.
/// Kitchen staff see this screen but only get the Food tab (no tab bar).
class AdminOrdersScreen extends ConsumerStatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  ConsumerState<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends ConsumerState<AdminOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Widget _liveDot(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.emerald,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Live',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppColors.emerald,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).valueOrNull;
    final isKitchenStaff = profile?.isKitchenStaff ?? false;

    // Kitchen staff: single-tab view — no tab bar shown.
    if (isKitchenStaff) {
      return Scaffold(
        appBar: UniflexAppBar(
          title: 'Orders',
          actions: [_liveDot(context)],
        ),
        body: const KitchenQueueBody(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [_liveDot(context)],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Food'),
            Tab(text: 'Deliveries'),
            Tab(text: 'Errands'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          KitchenQueueBody(),
          _DeliveriesTab(),
          _ErrandsTab(),
        ],
      ),
    );
  }
}

// ── Shared helpers ─────────────────────────────────────────────────────────

/// Shows a cancel confirmation dialog with an optional reason field.
/// Returns after the action completes (or is dismissed).
Future<void> _showAdminCancelDialog(
  BuildContext context, {
  required String title,
  required Future<void> Function(String? reason) onCancel,
  required void Function() onDone,
}) async {
  final reasonCtrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: reasonCtrl,
        maxLines: 2,
        decoration: const InputDecoration(
          labelText: 'Reason (optional)',
          hintText: 'e.g. Student requested cancellation',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Keep'),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Cancel Order'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final reason =
      reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null;
  try {
    await onCancel(reason);
    onDone();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel: $e')),
      );
    }
  }
}

/// Filter chip bar shared by both Deliveries and Errands tabs.
class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final int selected;
  final List<String> labels;
  final void Function(int) onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (_, i) => FilterChip(
          label: Text(labels[i]),
          selected: selected == i,
          onSelected: (_) => onSelect(i),
        ),
      ),
    );
  }
}

// ── Deliveries tab ─────────────────────────────────────────────────────────

enum _DeliveryFilter { all, waiting, withRider }

class _DeliveriesTab extends ConsumerStatefulWidget {
  const _DeliveriesTab();

  @override
  ConsumerState<_DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends ConsumerState<_DeliveriesTab> {
  _DeliveryFilter _filter = _DeliveryFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupsAsync = ref.watch(adminDeliveryGroupsProvider);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RetrySection(
        message: 'Could not load deliveries.',
        onRetry: () => ref.invalidate(adminDeliveryGroupsProvider),
      ),
      data: (groups) {
        final filtered = switch (_filter) {
          _DeliveryFilter.all => groups,
          _DeliveryFilter.waiting =>
            groups.where((r) => r.group.riderId == null).toList(),
          _DeliveryFilter.withRider =>
            groups.where((r) => r.group.riderId != null).toList(),
        };

        return Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _FilterBar(
              selected: _filter.index,
              labels: const ['All', 'Waiting', 'With Rider'],
              onSelect: (i) =>
                  setState(() => _filter = _DeliveryFilter.values[i]),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No active deliveries',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenGutter,
                        0,
                        AppSpacing.screenGutter,
                        AppSpacing.xl,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) =>
                          _DeliveryGroupCard(row: filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryGroupCard extends ConsumerStatefulWidget {
  const _DeliveryGroupCard({required this.row});
  final AdminDeliveryGroupRow row;

  @override
  ConsumerState<_DeliveryGroupCard> createState() => _DeliveryGroupCardState();
}

class _DeliveryGroupCardState extends ConsumerState<_DeliveryGroupCard> {
  bool _isCancelling = false;

  Future<void> _cancel() async {
    setState(() => _isCancelling = true);
    await _showAdminCancelDialog(
      context,
      title: 'Cancel this delivery?',
      onCancel: (reason) => ref
          .read(adminServiceProvider)
          .adminCancelDeliveryGroup(widget.row.group.id, reason: reason),
      onDone: () {
        ref.invalidate(adminDeliveryGroupsProvider);
        if (mounted) setState(() => _isCancelling = false);
      },
    );
    if (mounted) setState(() => _isCancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final group = row.group;

    final statusColor = switch (group.status) {
      DeliveryGroupStatus.placed => AppColors.orange,
      DeliveryGroupStatus.commitmentPaid => theme.colorScheme.primary,
      DeliveryGroupStatus.awaitingFinalPayment => AppColors.info,
      DeliveryGroupStatus.outForDelivery => AppColors.emerald,
      _ => theme.colorScheme.outline,
    };

    final vendorLabel = row.vendorNames.isEmpty
        ? 'Unknown vendor'
        : row.vendorNames.join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    group.status.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  group.shortId,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Vendors
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.storefront_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${row.legCount} ${row.legCount == 1 ? 'stop' : 'stops'} · $vendorLabel',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            if (group.deliveryLocation != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      group.deliveryLocation!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            if (group.studentNote != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined,
                      size: 14,
                      color: AppColors.warning.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      group.studentNote!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Footer: rider status + cancel
            Row(
              children: [
                Icon(
                  group.riderId == null
                      ? Icons.hourglass_empty_outlined
                      : Icons.two_wheeler_outlined,
                  size: 14,
                  color: group.riderId == null
                      ? AppColors.orange
                      : AppColors.emerald,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group.riderId == null
                        ? 'No rider yet'
                        : 'Rider assigned',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: group.riderId == null
                          ? AppColors.orange
                          : AppColors.emerald,
                    ),
                  ),
                ),
                if (!group.isTerminal)
                  TextButton.icon(
                    onPressed: _isCancelling ? null : _cancel,
                    icon: _isCancelling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Errands tab ────────────────────────────────────────────────────────────

enum _ErrandFilter { all, open, inProgress }

class _ErrandsTab extends ConsumerStatefulWidget {
  const _ErrandsTab();

  @override
  ConsumerState<_ErrandsTab> createState() => _ErrandsTabState();
}

class _ErrandsTabState extends ConsumerState<_ErrandsTab> {
  _ErrandFilter _filter = _ErrandFilter.all;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errandsAsync = ref.watch(adminErrandOrdersProvider);

    return errandsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RetrySection(
        message: 'Could not load errands.',
        onRetry: () => ref.invalidate(adminErrandOrdersProvider),
      ),
      data: (errands) {
        final filtered = switch (_filter) {
          _ErrandFilter.all => errands,
          _ErrandFilter.open => errands
              .where((r) => r.order.status == OrderStatus.placed)
              .toList(),
          _ErrandFilter.inProgress => errands
              .where((r) =>
                  r.order.status == OrderStatus.beingSourced ||
                  r.order.status == OrderStatus.outForDelivery)
              .toList(),
        };

        return Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _FilterBar(
              selected: _filter.index,
              labels: const ['All', 'Open', 'In Progress'],
              onSelect: (i) =>
                  setState(() => _filter = _ErrandFilter.values[i]),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No active errands',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.screenGutter,
                        0,
                        AppSpacing.screenGutter,
                        AppSpacing.xl,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) =>
                          _ErrandOrderCard(row: filtered[i]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrandOrderCard extends ConsumerStatefulWidget {
  const _ErrandOrderCard({required this.row});
  final AdminErrandRow row;

  @override
  ConsumerState<_ErrandOrderCard> createState() => _ErrandOrderCardState();
}

class _ErrandOrderCardState extends ConsumerState<_ErrandOrderCard> {
  bool _isCancelling = false;

  Future<void> _cancel() async {
    setState(() => _isCancelling = true);
    await _showAdminCancelDialog(
      context,
      title: 'Cancel this errand?',
      onCancel: (reason) => ref
          .read(adminServiceProvider)
          .adminCancelOrder(widget.row.order.id, reason: reason),
      onDone: () {
        ref.invalidate(adminErrandOrdersProvider);
        if (mounted) setState(() => _isCancelling = false);
      },
    );
    if (mounted) setState(() => _isCancelling = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = widget.row;
    final order = row.order;

    final statusColor = switch (order.status) {
      OrderStatus.placed => AppColors.orange,
      OrderStatus.beingSourced => theme.colorScheme.primary,
      OrderStatus.outForDelivery => AppColors.emerald,
      _ => theme.colorScheme.outline,
    };

    final timeAgo = _timeAgo(order.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentViolet.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    'Errand',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.accentViolet,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Text(
                    order.status.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  order.shortId,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Category + time
            if (row.category != null)
              Text(
                '${row.category!.replaceAll('_', ' ')} · $timeAgo',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            const SizedBox(height: 4),
            // Pickup
            if (row.pickupLocation != null)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.upload_outlined,
                      size: 14,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.pickupLocation!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            // Drop-off
            if (order.deliveryLocation != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on_outlined,
                      size: 14,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.deliveryLocation!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            // Item description
            if (row.itemDescription != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.description_outlined,
                      size: 14,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      row.itemDescription!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Footer: rider status + cancel
            Row(
              children: [
                Icon(
                  order.riderId == null
                      ? Icons.hourglass_empty_outlined
                      : Icons.two_wheeler_outlined,
                  size: 14,
                  color: order.riderId == null
                      ? AppColors.orange
                      : AppColors.emerald,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    order.riderId == null
                        ? 'No rider yet'
                        : 'Rider assigned',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: order.riderId == null
                          ? AppColors.orange
                          : AppColors.emerald,
                    ),
                  ),
                ),
                if (!order.status.isTerminal)
                  TextButton.icon(
                    onPressed: _isCancelling ? null : _cancel,
                    icon: _isCancelling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ago';
  }
}
