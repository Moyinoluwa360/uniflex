import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/accordions/app_accordion_card.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../services/admin_providers.dart';

// ── Detail data models ────────────────────────────────────────────────────────

class _ProfileSnap {
  const _ProfileSnap({
    required this.fullName,
    this.nickname,
    this.phone,
    this.email,
  });
  final String fullName;
  final String? nickname;
  final String? phone;
  final String? email;

  String get displayName => nickname?.isNotEmpty == true ? nickname! : fullName;
}

class _LegData {
  const _LegData({
    required this.order,
    required this.vendorName,
    required this.vendorLocation,
    required this.items,
    required this.packs,
  });
  final Order order;
  final String vendorName;
  final String? vendorLocation;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> packs;
}

// ── Providers ─────────────────────────────────────────────────────────────────

final _groupLegsProvider =
    FutureProvider.autoDispose.family<List<_LegData>, String>((ref, groupId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('orders')
      .select('*, vendors(name, location), order_items(*), order_packs(*)')
      .eq('delivery_group_id', groupId)
      .order('created_at');

  return rows.map((m) {
    final vendor = m['vendors'] as Map<String, dynamic>?;
    final rawItems = (m['order_items'] as List?) ?? [];
    final rawPacks = (m['order_packs'] as List?) ?? [];
    return _LegData(
      order: Order.fromMap(m),
      vendorName: vendor?['name'] as String? ?? 'Unknown vendor',
      vendorLocation: vendor?['location'] as String?,
      items: rawItems.cast<Map<String, dynamic>>(),
      packs: rawPacks.cast<Map<String, dynamic>>(),
    );
  }).toList();
});

final _profileProvider =
    FutureProvider.autoDispose.family<_ProfileSnap, String>((ref, userId) async {
  final client = ref.watch(supabaseClientProvider);
  final row = await client
      .from('profiles')
      .select('full_name, nickname, phone, email')
      .eq('id', userId)
      .single();
  return _ProfileSnap(
    fullName: row['full_name'] as String? ?? '—',
    nickname: row['nickname'] as String?,
    phone: row['phone'] as String?,
    email: row['email'] as String?,
  );
});

final _errandRequestProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from('errand_requests')
      .select('category, item_description, pickup_location, dropoff_location')
      .eq('order_id', orderId);
  if (rows.isEmpty) return null;
  return Map<String, dynamic>.from(rows.first);
});

// ── Main screen ────────────────────────────────────────────────────────────────

/// Full detail view for one delivery group or one errand order.
class AdminOrderDetailsScreen extends ConsumerStatefulWidget {
  /// For a delivery group (food delivery).
  const AdminOrderDetailsScreen.group({super.key, required DeliveryGroup group})
      : group = group,
        order = null;

  /// For a standalone errand order.
  const AdminOrderDetailsScreen.order({super.key, required Order order})
      : order = order,
        group = null;

  final DeliveryGroup? group;
  final Order? order;

  @override
  ConsumerState<AdminOrderDetailsScreen> createState() =>
      _AdminOrderDetailsScreenState();
}

class _AdminOrderDetailsScreenState
    extends ConsumerState<AdminOrderDetailsScreen> {
  bool _isCancelling = false;
  // Track which accordion is expanded (index into legs list)
  int? _expandedLeg;

  bool get _isGroup => widget.group != null;

  String get _title =>
      _isGroup ? 'Order ${widget.group!.shortId}' : 'Errand ${widget.order!.shortId}';

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isGroup ? 'Cancel this delivery?' : 'Cancel this errand?'),
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
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    final reason =
        reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null;
    try {
      final client = ref.read(supabaseClientProvider);
      if (_isGroup) {
        await client.rpc('admin_cancel_delivery_group', params: {
          'p_group_id': widget.group!.id,
          'p_reason': reason,
        });
      } else {
        await ref.read(adminServiceProvider).adminCancelOrder(
              widget.order!.id,
              reason: reason,
            );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UniflexAppBar(title: _title),
      body: _isGroup ? _buildGroupBody() : _buildErrandBody(),
    );
  }

  // ── Delivery group body ──────────────────────────────────────────────────

  Widget _buildGroupBody() {
    final group = widget.group!;
    final legsAsync = ref.watch(_groupLegsProvider(group.id));
    final customerAsync = ref.watch(_profileProvider(group.studentId));
    final riderAsync = group.riderId != null
        ? ref.watch(_profileProvider(group.riderId!))
        : null;

    return legsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => RetrySection(
        message: 'Could not load order details.',
        onRetry: () => ref.invalidate(_groupLegsProvider(group.id)),
      ),
      data: (legs) {
        final isTerminal = group.isTerminal;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenGutter,
            AppSpacing.md,
            AppSpacing.screenGutter,
            AppSpacing.xl,
          ),
          children: [
            // Status badge
            _StatusBadge(statusLabel: group.status.label, color: _groupStatusColor(group.status)),
            const SizedBox(height: AppSpacing.lg),

            // Customer
            _SectionHeader(title: 'Customer'),
            const SizedBox(height: AppSpacing.sm),
            customerAsync.when(
              loading: () => const _InfoRow(icon: Icons.person_outline, text: 'Loading…'),
              error: (_, __) =>
                  _InfoRow(icon: Icons.person_outline, text: 'ID: ${group.studentId.substring(0, 8)}'),
              data: (p) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.person_outline, text: p.displayName),
                  if (p.phone != null)
                    _InfoRow(icon: Icons.phone_outlined, text: p.phone!),
                  if (p.email != null)
                    _InfoRow(icon: Icons.email_outlined, text: p.email!),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Delivery info
            _SectionHeader(title: 'Delivery'),
            const SizedBox(height: AppSpacing.sm),
            if (group.deliveryLocation != null)
              _InfoRow(icon: Icons.location_on_outlined, text: group.deliveryLocation!),
            if (group.locationDetails != null)
              _InfoRow(icon: Icons.info_outline, text: group.locationDetails!),
            if (group.studentNote != null)
              _InfoRow(
                icon: Icons.sticky_note_2_outlined,
                text: group.studentNote!,
                color: AppColors.warning,
              ),
            const SizedBox(height: AppSpacing.lg),

            // Rider
            _SectionHeader(title: 'Rider'),
            const SizedBox(height: AppSpacing.sm),
            if (riderAsync == null)
              const _InfoRow(
                icon: Icons.hourglass_empty_outlined,
                text: 'Waiting for rider',
              )
            else
              riderAsync.when(
                loading: () =>
                    const _InfoRow(icon: Icons.two_wheeler_outlined, text: 'Loading rider…'),
                error: (_, __) =>
                    const _InfoRow(icon: Icons.two_wheeler_outlined, text: 'Rider assigned'),
                data: (p) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(icon: Icons.two_wheeler_outlined, text: p.displayName),
                    if (p.phone != null)
                      _InfoRow(icon: Icons.phone_outlined, text: p.phone!),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            // Items
            _SectionHeader(title: 'Items'),
            const SizedBox(height: AppSpacing.sm),
            if (legs.length == 1)
              _SingleVendorItems(leg: legs.first)
            else
              _MultiVendorAccordions(
                legs: legs,
                expandedIndex: _expandedLeg,
                onToggle: (i) =>
                    setState(() => _expandedLeg = _expandedLeg == i ? null : i),
              ),
            const SizedBox(height: AppSpacing.lg),

            // Fees
            _SectionHeader(title: 'Fees'),
            const SizedBox(height: AppSpacing.sm),
            _FeesSection(group: group),
            const SizedBox(height: AppSpacing.lg),

            // Timeline
            _SectionHeader(title: 'Timeline'),
            const SizedBox(height: AppSpacing.sm),
            _GroupTimeline(group: group),
            const SizedBox(height: AppSpacing.lg),

            // Cancel
            if (!isTerminal)
              _CancelButton(
                isCancelling: _isCancelling,
                onCancel: _cancel,
              ),
          ],
        );
      },
    );
  }

  // ── Errand body ──────────────────────────────────────────────────────────

  Widget _buildErrandBody() {
    final order = widget.order!;
    final customerAsync = ref.watch(_profileProvider(order.studentId));
    final requestAsync = ref.watch(_errandRequestProvider(order.id));
    final riderAsync = order.riderId != null
        ? ref.watch(_profileProvider(order.riderId!))
        : null;

    final isTerminal = order.status.isTerminal;
    final statusColor = _errandStatusColor(order.status);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.md,
        AppSpacing.screenGutter,
        AppSpacing.xl,
      ),
      children: [
        // Status badge
        _StatusBadge(statusLabel: order.status.label, color: statusColor),
        const SizedBox(height: AppSpacing.lg),

        // Customer
        _SectionHeader(title: 'Customer'),
        const SizedBox(height: AppSpacing.sm),
        customerAsync.when(
          loading: () => const _InfoRow(icon: Icons.person_outline, text: 'Loading…'),
          error: (_, __) =>
              _InfoRow(icon: Icons.person_outline, text: 'ID: ${order.studentId.substring(0, 8)}'),
          data: (p) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _InfoRow(icon: Icons.person_outline, text: p.displayName),
              if (p.phone != null) _InfoRow(icon: Icons.phone_outlined, text: p.phone!),
              if (p.email != null) _InfoRow(icon: Icons.email_outlined, text: p.email!),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Errand details
        _SectionHeader(title: 'Errand Details'),
        const SizedBox(height: AppSpacing.sm),
        requestAsync.when(
          loading: () => const _InfoRow(icon: Icons.info_outline, text: 'Loading…'),
          error: (_, __) => const SizedBox.shrink(),
          data: (req) {
            if (req == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (req['category'] != null)
                  _InfoRow(
                    icon: Icons.category_outlined,
                    text: (req['category'] as String).replaceAll('_', ' '),
                  ),
                if (req['item_description'] != null)
                  _InfoRow(
                    icon: Icons.description_outlined,
                    text: req['item_description'] as String,
                  ),
                if (req['pickup_location'] != null)
                  _InfoRow(
                    icon: Icons.upload_outlined,
                    text: req['pickup_location'] as String,
                  ),
                if (req['dropoff_location'] != null)
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: req['dropoff_location'] as String,
                  ),
              ],
            );
          },
        ),
        if (order.deliveryLocation != null)
          _InfoRow(icon: Icons.location_on_outlined, text: order.deliveryLocation!),
        if (order.notes != null)
          _InfoRow(
            icon: Icons.sticky_note_2_outlined,
            text: order.notes!,
            color: AppColors.warning,
          ),
        const SizedBox(height: AppSpacing.lg),

        // Rider
        _SectionHeader(title: 'Rider'),
        const SizedBox(height: AppSpacing.sm),
        if (riderAsync == null)
          const _InfoRow(icon: Icons.hourglass_empty_outlined, text: 'Waiting for rider')
        else
          riderAsync.when(
            loading: () =>
                const _InfoRow(icon: Icons.two_wheeler_outlined, text: 'Loading rider…'),
            error: (_, __) =>
                const _InfoRow(icon: Icons.two_wheeler_outlined, text: 'Rider assigned'),
            data: (p) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(icon: Icons.two_wheeler_outlined, text: p.displayName),
                if (p.phone != null) _InfoRow(icon: Icons.phone_outlined, text: p.phone!),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),

        // Fees
        _SectionHeader(title: 'Fees'),
        const SizedBox(height: AppSpacing.sm),
        _ErrandFeesSection(order: order),
        const SizedBox(height: AppSpacing.lg),

        // Timeline
        _SectionHeader(title: 'Timeline'),
        const SizedBox(height: AppSpacing.sm),
        _ErrandTimeline(order: order),
        const SizedBox(height: AppSpacing.lg),

        // Cancel
        if (!isTerminal)
          _CancelButton(isCancelling: _isCancelling, onCancel: _cancel),
      ],
    );
  }

  // ── Colour helpers ────────────────────────────────────────────────────────

  Color _groupStatusColor(DeliveryGroupStatus s) {
    return switch (s) {
      DeliveryGroupStatus.placed => AppColors.orange,
      DeliveryGroupStatus.commitmentPaid ||
      DeliveryGroupStatus.riderAccepted =>
        Theme.of(context).colorScheme.primary,
      DeliveryGroupStatus.awaitingFinalPayment => AppColors.info,
      DeliveryGroupStatus.outForDelivery => AppColors.emerald,
      DeliveryGroupStatus.completed => AppColors.emerald,
      DeliveryGroupStatus.cancelled => Theme.of(context).colorScheme.error,
    };
  }

  Color _errandStatusColor(OrderStatus s) {
    return switch (s) {
      OrderStatus.placed => AppColors.orange,
      OrderStatus.beingSourced => Theme.of(context).colorScheme.primary,
      OrderStatus.outForDelivery => AppColors.emerald,
      OrderStatus.completed => AppColors.emerald,
      OrderStatus.cancelled => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      title,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        letterSpacing: 0.5,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.text,
    this.color,
  });
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurface.withValues(alpha: 0.5);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: color != null
                    ? color
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.statusLabel, required this.color});
  final String statusLabel;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs + 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          statusLabel,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  const _CancelButton({required this.isCancelling, required this.onCancel});
  final bool isCancelling;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: isCancelling ? null : onCancel,
        icon: isCancelling
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cancel_outlined),
        label: Text(isCancelling ? 'Cancelling…' : 'Cancel Order'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          minimumSize: const Size(double.infinity, AppSpacing.controlHeight),
        ),
      ),
    );
  }
}

// ── Items widgets ─────────────────────────────────────────────────────────────

class _SingleVendorItems extends StatelessWidget {
  const _SingleVendorItems({required this.leg});
  final _LegData leg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (leg.items.isEmpty && leg.packs.isEmpty) {
      return Text(
        'No items',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leg.packs.isNotEmpty) ...[
          _buildItemList(context, leg.packs, isPack: true),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (leg.items.isNotEmpty) _buildItemList(context, leg.items, isPack: false),
      ],
    );
  }

  Widget _buildItemList(BuildContext context, List<Map<String, dynamic>> rows,
      {required bool isPack}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows.map((item) {
        final name = item['name'] as String? ??
            item['product_name'] as String? ??
            (isPack ? 'Pack' : 'Item');
        final qty = item['quantity'] as int? ?? 1;
        final price = (item['unit_price'] as num?)?.toDouble() ??
            (item['price'] as num?)?.toDouble() ??
            0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(
                isPack ? Icons.inventory_2_outlined : Icons.fastfood_outlined,
                size: 14,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$qty× $name',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Text(
                '₦${(price * qty).toStringAsFixed(0)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _MultiVendorAccordions extends StatelessWidget {
  const _MultiVendorAccordions({
    required this.legs,
    required this.expandedIndex,
    required this.onToggle,
  });
  final List<_LegData> legs;
  final int? expandedIndex;
  final void Function(int) onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(legs.length, (i) {
        final leg = legs[i];
        final isExpanded = expandedIndex == i;
        final itemCount = leg.items.length + leg.packs.length;
        return AppAccordionCard(
          isExpanded: isExpanded,
          onTap: () => onToggle(i),
          leading: buildAccordionLeadingIcon(
            context: context,
            icon: Icons.storefront_outlined,
          ),
          title: leg.vendorName,
          subtitle: '$itemCount item${itemCount == 1 ? '' : 's'}',
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              0,
            ),
            child: _SingleVendorItems(leg: leg),
          ),
        );
      }),
    );
  }
}

// ── Fee sections ──────────────────────────────────────────────────────────────

class _FeesSection extends StatelessWidget {
  const _FeesSection({required this.group});
  final DeliveryGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FeeRow(
          label: 'Delivery fee',
          amount: group.commitmentFeeTotal,
          paid: true,
        ),
        if (group.finalAmount != null)
          _FeeRow(
            label: 'Final price',
            amount: group.finalAmount!,
            paid: group.finalPaymentPaid,
          )
        else
          Text(
            'Final price: pending',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}

class _ErrandFeesSection extends StatelessWidget {
  const _ErrandFeesSection({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FeeRow(
          label: 'Service fee',
          amount: order.commitmentFeeAmount,
          paid: order.commitmentFeePaid,
        ),
        if (order.finalAmount != null)
          _FeeRow(
            label: 'Final amount',
            amount: order.finalAmount!,
            paid: order.finalPaymentPaid,
          )
        else
          Text(
            'Final amount: pending',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
      ],
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({
    required this.label,
    required this.amount,
    required this.paid,
  });
  final String label;
  final double amount;
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '₦${amount.toStringAsFixed(0)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: 2),
            decoration: BoxDecoration(
              color: (paid ? AppColors.emerald : AppColors.orange)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              paid ? 'paid' : 'pending',
              style: theme.textTheme.labelSmall?.copyWith(
                color: paid ? AppColors.emerald : AppColors.orange,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Timelines ─────────────────────────────────────────────────────────────────

class _GroupTimeline extends StatelessWidget {
  const _GroupTimeline({required this.group});
  final DeliveryGroup group;

  @override
  Widget build(BuildContext context) {
    final events = <_TimelineEvent>[];

    events.add(_TimelineEvent(
      label: 'Order placed',
      time: group.createdAt,
      icon: Icons.shopping_cart_outlined,
      color: AppColors.orange,
    ));

    if (group.status.index >= DeliveryGroupStatus.commitmentPaid.index) {
      events.add(_TimelineEvent(
        label: 'Commitment fee paid',
        time: null,
        icon: Icons.payments_outlined,
        color: Theme.of(context).colorScheme.primary,
      ));
    }
    if (group.status.index >= DeliveryGroupStatus.riderAccepted.index) {
      events.add(_TimelineEvent(
        label: 'Rider accepted',
        time: null,
        icon: Icons.two_wheeler_outlined,
        color: Theme.of(context).colorScheme.primary,
      ));
    }
    if (group.status == DeliveryGroupStatus.outForDelivery ||
        group.status == DeliveryGroupStatus.completed) {
      events.add(_TimelineEvent(
        label: 'Out for delivery',
        time: null,
        icon: Icons.delivery_dining_outlined,
        color: AppColors.emerald,
      ));
    }
    if (group.status == DeliveryGroupStatus.completed) {
      events.add(_TimelineEvent(
        label: 'Delivered',
        time: null,
        icon: Icons.check_circle_outline,
        color: AppColors.emerald,
      ));
    }
    if (group.status == DeliveryGroupStatus.cancelled) {
      events.add(_TimelineEvent(
        label: group.cancelledByStudent ? 'Cancelled by student' : 'Cancelled by admin',
        time: null,
        icon: Icons.cancel_outlined,
        color: Theme.of(context).colorScheme.error,
      ));
    }

    return _TimelineList(events: events);
  }
}

class _ErrandTimeline extends StatelessWidget {
  const _ErrandTimeline({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final events = <_TimelineEvent>[
      _TimelineEvent(
        label: 'Errand placed',
        time: order.createdAt,
        icon: Icons.shopping_bag_outlined,
        color: AppColors.orange,
      ),
    ];

    if (order.status.index >= OrderStatus.beingSourced.index) {
      events.add(_TimelineEvent(
        label: 'Being sourced',
        time: null,
        icon: Icons.search_outlined,
        color: Theme.of(context).colorScheme.primary,
      ));
    }
    if (order.status == OrderStatus.outForDelivery ||
        order.status == OrderStatus.completed) {
      events.add(_TimelineEvent(
        label: 'Out for delivery',
        time: null,
        icon: Icons.delivery_dining_outlined,
        color: AppColors.emerald,
      ));
    }
    if (order.status == OrderStatus.completed) {
      events.add(_TimelineEvent(
        label: 'Completed',
        time: null,
        icon: Icons.check_circle_outline,
        color: AppColors.emerald,
      ));
    }
    if (order.status == OrderStatus.cancelled) {
      events.add(_TimelineEvent(
        label: 'Cancelled',
        time: null,
        icon: Icons.cancel_outlined,
        color: Theme.of(context).colorScheme.error,
      ));
    }

    return _TimelineList(events: events);
  }
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.label,
    required this.time,
    required this.icon,
    required this.color,
  });
  final String label;
  final DateTime? time;
  final IconData icon;
  final Color color;
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.events});
  final List<_TimelineEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: List.generate(events.length, (i) {
        final e = events[i];
        final isLast = i == events.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: e.color.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(e.icon, size: 14, color: e.color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 1.5,
                            color: theme.dividerColor,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: isLast ? 0 : AppSpacing.md, top: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (e.time != null)
                        Text(
                          _fmt(e.time!),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _fmt(DateTime dt) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]}, '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}
