import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/admin_providers.dart';
import '../services/admin_service.dart';
import '../services/profile_basics.dart';
import 'admin_order_details_screen.dart';
import '../../shared/widgets/inputs/app_text_field.dart';

/// Tabbed order management screen for admin: Deliveries | Errands.
///
/// Each tab has three filter chips (Active / Completed / Cancelled) and
/// a search bar. Cards navigate to [AdminOrderDetailsScreen] on tap.
///
/// Kitchen Queue content has been removed — it lives in the separate
/// AdminScheduledOrdersScreen and KitchenQueueScreen.
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
    _tabs = TabController(length: 2, vsync: this);
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
            decoration: BoxDecoration(
              color: context.colors.brandText,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Live',
            style: theme.textTheme.labelSmall?.copyWith(
              color: context.colors.brandText,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders'),
        actions: [_liveDot(context)],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Deliveries'),
            Tab(text: 'Errands'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _DeliveriesTab(),
          _ErrandsTab(),
        ],
      ),
    );
  }
}

// ── Filter chip bar ───────────────────────────────────────────────────────────

/// The rider line on an order card: the rider's name once one has accepted,
/// "Waiting for rider" before that. (Falls back to "Rider assigned" only if
/// the name could not be loaded.)
String riderLineText(String? riderId, String? riderName) {
  if (riderId == null) return 'Waiting for rider';
  final name = riderName?.trim();
  return (name == null || name.isEmpty) ? 'Rider assigned' : 'Rider: $name';
}

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

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenGutter),
      child: AppTextField(
        controller: controller,
        onChanged: onChanged,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'Search by ID or customer',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          isDense: true,
        ),
      ),
    );
  }
}

// ── Deliveries tab ────────────────────────────────────────────────────────────

enum _StatusFilter { active, completed, cancelled }

class _DeliveriesTab extends ConsumerStatefulWidget {
  const _DeliveriesTab();

  @override
  ConsumerState<_DeliveriesTab> createState() => _DeliveriesTabState();
}

class _DeliveriesTabState extends ConsumerState<_DeliveriesTab> {
  _StatusFilter _filter = _StatusFilter.active;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilter(DeliveryGroup group) {
    return switch (_filter) {
      _StatusFilter.active => !group.isTerminal,
      _StatusFilter.completed => group.status == DeliveryGroupStatus.completed,
      _StatusFilter.cancelled => group.status == DeliveryGroupStatus.cancelled,
    };
  }

  bool _matchesQuery(AdminDeliveryGroupRow row) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return row.group.shortId.toLowerCase().contains(q) ||
        row.group.id.toLowerCase().contains(q) ||
        row.vendorNames.any((n) => n.toLowerCase().contains(q));
  }

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
        final filtered = groups
            .where((r) => _matchesFilter(r.group) && _matchesQuery(r))
            .toList();
        final riderNames = ref
                .watch(adminProfileBasicsProvider(
                    profileIdsKey(filtered.map((r) => r.group.riderId))))
                .valueOrNull ??
            const <String, ProfileBasics>{};

        return Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _FilterBar(
              selected: _filter.index,
              labels: const ['Active', 'Completed', 'Cancelled'],
              onSelect: (i) =>
                  setState(() => _filter = _StatusFilter.values[i]),
            ),
            const SizedBox(height: AppSpacing.xs),
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No ${_filter.name} deliveries',
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
                      itemBuilder: (_, i) => _DeliveryGroupCard(
                        row: filtered[i],
                        riderName: riderNames[filtered[i].group.riderId]
                            ?.displayName(),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _DeliveryGroupCard extends StatelessWidget {
  const _DeliveryGroupCard({required this.row, this.riderName});
  final AdminDeliveryGroupRow row;

  /// The rider's name once known; null while loading / unavailable.
  final String? riderName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final group = row.group;

    final statusColor = switch (group.status) {
      DeliveryGroupStatus.placed => context.colors.statusAmber,
      DeliveryGroupStatus.commitmentPaid ||
      DeliveryGroupStatus.riderAccepted =>
        theme.colorScheme.primary,
      DeliveryGroupStatus.awaitingFinalPayment => context.colors.textSecondary,
      DeliveryGroupStatus.outForDelivery => context.colors.brandText,
      DeliveryGroupStatus.completed => context.colors.brandText,
      DeliveryGroupStatus.cancelled => theme.colorScheme.error,
    };

    final vendorLabel = row.vendorNames.isEmpty
        ? 'Unknown vendor'
        : row.vendorNames.join(' · ');

    final timeAgo = _timeAgo(group.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: context.colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminOrderDetailsScreen.group(group: group),
        )),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: status badge + short ID + time
              Row(
                children: [
                  _StatusChip(label: group.status.label, color: statusColor),
                  const Spacer(),
                  Text(
                    group.shortId,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    timeAgo,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
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
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.5)),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // Footer: rider
              Row(
                children: [
                  Icon(
                    group.riderId == null
                        ? Icons.hourglass_empty_outlined
                        : Icons.two_wheeler_outlined,
                    size: 14,
                    color: group.riderId == null
                        ? context.colors.statusAmber
                        : context.colors.brandText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    riderLineText(group.riderId, riderName),
                    key: const ValueKey('rider-line'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: group.riderId == null
                          ? context.colors.statusAmber
                          : context.colors.brandText,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── Errands tab ───────────────────────────────────────────────────────────────

class _ErrandsTab extends ConsumerStatefulWidget {
  const _ErrandsTab();

  @override
  ConsumerState<_ErrandsTab> createState() => _ErrandsTabState();
}

class _ErrandsTabState extends ConsumerState<_ErrandsTab> {
  _StatusFilter _filter = _StatusFilter.active;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesFilter(Order order) {
    return switch (_filter) {
      _StatusFilter.active => !order.status.isTerminal,
      _StatusFilter.completed => order.status == OrderStatus.completed,
      _StatusFilter.cancelled => order.status == OrderStatus.cancelled,
    };
  }

  bool _matchesQuery(AdminErrandRow row) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return row.order.shortId.toLowerCase().contains(q) ||
        row.order.id.toLowerCase().contains(q) ||
        (row.category?.toLowerCase().contains(q) ?? false);
  }

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
        final filtered = errands
            .where((r) => _matchesFilter(r.order) && _matchesQuery(r))
            .toList();
        final riderNames = ref
                .watch(adminProfileBasicsProvider(
                    profileIdsKey(filtered.map((r) => r.order.riderId))))
                .valueOrNull ??
            const <String, ProfileBasics>{};

        return Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            _FilterBar(
              selected: _filter.index,
              labels: const ['Active', 'Completed', 'Cancelled'],
              onSelect: (i) =>
                  setState(() => _filter = _StatusFilter.values[i]),
            ),
            const SizedBox(height: AppSpacing.xs),
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No ${_filter.name} errands',
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
                      itemBuilder: (_, i) => _ErrandOrderCard(
                        row: filtered[i],
                        riderName: riderNames[filtered[i].order.riderId]
                            ?.displayName(),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _ErrandOrderCard extends StatelessWidget {
  const _ErrandOrderCard({required this.row, this.riderName});
  final AdminErrandRow row;

  /// The rider's name once known; null while loading / unavailable.
  final String? riderName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = row.order;

    final statusColor = switch (order.status) {
      OrderStatus.placed => context.colors.statusAmber,
      OrderStatus.beingSourced => theme.colorScheme.primary,
      OrderStatus.outForDelivery => context.colors.brandText,
      OrderStatus.completed => context.colors.brandText,
      OrderStatus.cancelled => theme.colorScheme.error,
      _ => theme.colorScheme.outline,
    };

    final timeAgo = _timeAgo(order.createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: context.colors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AdminOrderDetailsScreen.order(order: order),
        )),
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
                      color: context.colors.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      'Errand',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: context.colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _StatusChip(label: order.status.label, color: statusColor),
                  const Spacer(),
                  Text(
                    order.shortId,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    timeAgo,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              // Category
              if (row.category != null)
                Row(
                  children: [
                    Icon(Icons.category_outlined,
                        size: 14,
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Text(
                      row.category!.replaceAll('_', ' '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              // Pickup location
              if (row.pickupLocation != null) ...[
                const SizedBox(height: 4),
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              // Footer: rider
              Row(
                children: [
                  Icon(
                    order.riderId == null
                        ? Icons.hourglass_empty_outlined
                        : Icons.two_wheeler_outlined,
                    size: 14,
                    color: order.riderId == null
                        ? context.colors.statusAmber
                        : context.colors.brandText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      riderLineText(order.riderId, riderName),
                      key: const ValueKey('rider-line'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: order.riderId == null
                            ? context.colors.statusAmber
                            : context.colors.brandText,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
}

// ── Shared chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
