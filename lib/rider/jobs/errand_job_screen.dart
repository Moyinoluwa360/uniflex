import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../services/rider_providers.dart';
import '../services/rider_service.dart';

class ErrandJobScreen extends ConsumerStatefulWidget {
  /// Open in preview mode (from pool — errand not yet accepted).
  ErrandJobScreen.fromPool({super.key, required Order order})
      : orderId = order.id,
        order = order,
        isPreview = true;

  /// Open as active errand (already accepted by this rider).
  const ErrandJobScreen.active({super.key, required this.orderId})
      : order = null,
        isPreview = false;

  final String orderId;
  final Order? order;
  final bool isPreview;

  @override
  ConsumerState<ErrandJobScreen> createState() => _ErrandJobScreenState();
}

class _ErrandJobScreenState extends ConsumerState<ErrandJobScreen> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref.read(riderServiceProvider).acceptOrder(widget.orderId);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                ErrandJobScreen.active(orderId: widget.orderId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _showDeliveryPinSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _ErrandDeliveryPinSheet(orderId: widget.orderId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isPreview) {
      return _buildPreview(context);
    }
    return _buildActive(context);
  }

  Widget _buildPreview(BuildContext context) {
    final order = widget.order!;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Job Details',
        actions: [_ErrandBadgeChip()],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                AppSpacing.xl,
              ),
              children: [
                _ErrandDetailCard(orderId: order.id),
                const SizedBox(height: AppSpacing.md),
                // Drop-off location.
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  label: 'Drop-off',
                  value: order.deliveryLocation ?? '—',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.lg,
            ),
            child: SizedBox(
              width: double.infinity,
              height: AppSpacing.controlHeight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                ),
                onPressed: _isAccepting ? null : _accept,
                child: _isAccepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite,
                        ),
                      )
                    : const Text('Accept Job'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActive(BuildContext context) {
    final theme = Theme.of(context);
    final detailAsync =
        ref.watch(activeDeliveryDetailProvider(widget.orderId));

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Active Errand',
        actions: [_ErrandBadgeChip()],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenGutter,
                AppSpacing.md,
                AppSpacing.screenGutter,
                AppSpacing.xl,
              ),
              children: [
                // Status stepper: 2 steps.
                _ErrandStatusStepper(detailAsync: detailAsync),
                const SizedBox(height: AppSpacing.lg),

                // Errand detail.
                _ErrandDetailCard(orderId: widget.orderId),
                const SizedBox(height: AppSpacing.md),

                // Customer card.
                detailAsync.when(
                  loading: () => const _DetailShimmer(),
                  error: (e, _) => RetrySection(
                    message: 'Could not load customer info.',
                    compact: true,
                    onRetry: () => ref.invalidate(
                        activeDeliveryDetailProvider(widget.orderId)),
                  ),
                  data: (detail) {
                    if (detail == null) return const SizedBox.shrink();
                    return _ActiveCustomerCard(detail: detail);
                  },
                ),
              ],
            ),
          ),

          // Bottom action: Enter Delivery PIN.
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenGutter,
              AppSpacing.sm,
              AppSpacing.screenGutter,
              AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              border: Border(top: BorderSide(color: theme.dividerColor)),
            ),
            child: SizedBox(
              width: double.infinity,
              height: AppSpacing.controlHeight,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                ),
                onPressed: _showDeliveryPinSheet,
                child: const Text('Enter Delivery PIN'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── ERRAND badge chip ─────────────────────────────────────────────────────────

class _ErrandBadgeChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentViolet.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          'ERRAND',
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppColors.accentViolet,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Status stepper (2 steps) ──────────────────────────────────────────────────

class _ErrandStatusStepper extends ConsumerWidget {
  const _ErrandStatusStepper({required this.detailAsync});

  final AsyncValue<ActiveDeliveryDetail?> detailAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Determine completed: check if the order is out_for_delivery vs accepted.
    final isOutForDelivery = detailAsync.valueOrNull?.order.status ==
        OrderStatus.outForDelivery;

    final steps = ['Accepted', 'Completed'];
    final current = isOutForDelivery ? 1 : 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentViolet.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
            color: AppColors.accentViolet.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            final stepIndex = i ~/ 2;
            final isActive = stepIndex < current;
            return Expanded(
              child: Container(
                height: 2,
                color: isActive
                    ? AppColors.accentViolet
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final isDone = stepIndex < current;
          final isCurrent = stepIndex == current;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone || isCurrent
                      ? AppColors.accentViolet
                      : theme.colorScheme.outline
                          .withValues(alpha: 0.2),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check,
                          size: 14, color: AppColors.pureWhite)
                      : isCurrent
                          ? const SizedBox(
                              width: 8,
                              height: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.pureWhite,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                steps[stepIndex],
                style: theme.textTheme.labelSmall?.copyWith(
                  color: isDone || isCurrent
                      ? AppColors.accentViolet
                      : theme.colorScheme.onSurface
                          .withValues(alpha: 0.4),
                  fontWeight:
                      isCurrent ? FontWeight.w700 : FontWeight.normal,
                  fontSize: 10,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Errand detail card (fetches from errand_requests) ────────────────────────

class _ErrandDetailCard extends ConsumerWidget {
  const _ErrandDetailCard({required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errandAsync =
        ref.watch(_errandRequestProvider(orderId));
    final theme = Theme.of(context);

    return errandAsync.when(
      loading: () => const _DetailShimmer(),
      error: (e, _) => RetrySection(
        message: 'Could not load errand details.',
        compact: true,
        onRetry: () =>
            ref.invalidate(_errandRequestProvider(orderId)),
      ),
      data: (data) {
        if (data == null) return const SizedBox.shrink();

        final category = data['category'] as String? ?? 'Errand';
        final description =
            data['item_description'] as String? ?? '—';
        final pickup = data['pickup_location'] as String?;

        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color:
                          AppColors.accentViolet.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      category,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppColors.accentViolet,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                description,
                style: theme.textTheme.bodyMedium,
              ),
              if (pickup != null && pickup.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.store_outlined,
                        size: 16,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.5)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pickup',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          Text(pickup,
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

final _errandRequestProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client
      .from('errand_requests')
      .select('order_id, pickup_location, item_description, category')
      .eq('order_id', orderId)
      .maybeSingle();
  return result;
});

// ── Active customer card ──────────────────────────────────────────────────────

class _ActiveCustomerCard extends StatelessWidget {
  const _ActiveCustomerCard({required this.detail});

  final ActiveDeliveryDetail detail;

  void _callPhone(BuildContext context, String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open phone app.')),
        );
      }
    }
  }

  void _openWhatsApp(BuildContext context, String phone) async {
    final formatted = phone.replaceFirst(RegExp(r'^0'), '234');
    final uri = Uri.parse('https://wa.me/$formatted');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot open WhatsApp.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = detail.customerPhone ?? '';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 16, color: AppColors.accentViolet),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Customer',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppColors.accentViolet,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (detail.customerName != null)
            Text(
              detail.customerName!,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          const SizedBox(height: AppSpacing.sm),

          // Drop-off location details from pickupAddress used as note.
          if (detail.pickupAddress != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    detail.pickupAddress!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          if (phone.isNotEmpty) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _callPhone(context, phone),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: const Text('Call'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openWhatsApp(context, phone),
                    icon: const Icon(Icons.chat_outlined, size: 16),
                    label: const Text('WhatsApp'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF25D366),
                      side: const BorderSide(
                          color: Color(0xFF25D366), width: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Info card ─────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 18,
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface
                        .withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shimmer placeholder ───────────────────────────────────────────────────────

class _DetailShimmer extends StatelessWidget {
  const _DetailShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.4),
      ),
    );
  }
}

// ── Delivery PIN bottom sheet (errand) ────────────────────────────────────────

class _ErrandDeliveryPinSheet extends ConsumerStatefulWidget {
  const _ErrandDeliveryPinSheet({required this.orderId});

  final String orderId;

  @override
  ConsumerState<_ErrandDeliveryPinSheet> createState() =>
      _ErrandDeliveryPinSheetState();
}

class _ErrandDeliveryPinSheetState
    extends ConsumerState<_ErrandDeliveryPinSheet> {
  final _controller = TextEditingController();
  bool _isConfirming = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final pin = _controller.text.trim().toUpperCase();
    if (pin.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter a 4-character PIN.')),
      );
      return;
    }

    setState(() => _isConfirming = true);
    try {
      await ref
          .read(riderServiceProvider)
          .verifyDelivery(widget.orderId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        Navigator.of(context).pop(); // close sheet
        Navigator.of(context).pop(); // pop job screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.screenGutter,
        right: AppSpacing.screenGutter,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Delivery PIN',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Ask the customer for their 4-digit PIN.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color:
                  theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            maxLength: 4,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: '- - - -',
              counterText: '',
            ),
            style: theme.textTheme.displaySmall?.copyWith(
              letterSpacing: 12,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
            autofocus: true,
            onChanged: (v) {
              final upper = v.toUpperCase();
              if (upper != v) {
                _controller.value = _controller.value.copyWith(
                  text: upper,
                  selection:
                      TextSelection.collapsed(offset: upper.length),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentViolet,
              ),
              onPressed: _isConfirming ? null : _confirm,
              child: _isConfirming
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite),
                    )
                  : const Text('Confirm delivery'),
            ),
          ),
        ],
      ),
    );
  }
}
