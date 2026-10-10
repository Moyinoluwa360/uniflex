import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/notify/message_customer_sheet.dart';
import '../services/rider_providers.dart';
import '../services/rider_service.dart';

/// Full delivery workflow screen. Progresses through two stages:
///   1. `accepted`  — rider navigates to pickup → taps "Confirm Pickup"
///   2. `picked_up` — rider navigates to customer → enters PIN to complete
///
/// Watches [activeDeliveriesProvider] for live stage updates so a background
/// refresh (e.g. from another device) is reflected instantly.
class ActiveDeliveryScreen extends ConsumerStatefulWidget {
  const ActiveDeliveryScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<ActiveDeliveryScreen> createState() =>
      _ActiveDeliveryScreenState();
}

class _ActiveDeliveryScreenState extends ConsumerState<ActiveDeliveryScreen> {
  bool _isConfirmingPickup = false;
  bool _isVerifying = false;

  Future<void> _confirmPickup() async {
    setState(() => _isConfirmingPickup = true);
    try {
      await ref.read(riderServiceProvider).confirmPickup(widget.orderId);
      // activeDeliveriesProvider will re-emit with updated delivery_stage.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm pickup: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isConfirmingPickup = false);
    }
  }

  Future<void> _showPinEntry(ActiveDeliveryDetail detail) async {
    final controller = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.screenGutter,
          right: AppSpacing.screenGutter,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Delivery PIN',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Ask the customer for the 4-character PIN shown in their app.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6),
                  ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              maxLength: 4,
              style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '• • • •',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Confirm Delivery'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;
    final pin = controller.text.trim();
    if (pin.length < 4) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter the full 4-character PIN')),
        );
      }
      return;
    }

    setState(() => _isVerifying = true);
    try {
      await ref.read(riderServiceProvider).verifyDelivery(widget.orderId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery completed!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains('Incorrect')
                  ? 'Incorrect PIN — ask the customer to check their app.'
                  : 'Verification failed: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _navigateTo(String destination) async {
    String mapsUrl;
    try {
      final permission = await Geolocator.checkPermission();
      final allowed = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (allowed) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 5),
          ),
        );
        mapsUrl = 'https://maps.google.com/?saddr=${pos.latitude},'
            '${pos.longitude}&daddr=${Uri.encodeComponent(destination)}'
            '&dirflg=d';
      } else {
        mapsUrl =
            'https://maps.google.com/?q=${Uri.encodeComponent(destination)}';
      }
    } catch (_) {
      mapsUrl =
          'https://maps.google.com/?q=${Uri.encodeComponent(destination)}';
    }

    final uri = Uri.parse(mapsUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _callCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  /// Messages the customer about this delivery. Useful for the things a
  /// status change cannot say — "I'm at the wrong gate", "traffic at the
  /// junction" — and it reaches them even with no phone number on file.
  Future<void> _messageCustomer(String orderId, String? customerName) async {
    final sent = await showMessageCustomerSheet(
      context,
      customerName: customerName,
      onSend: (message) => ref
          .read(riderServiceProvider)
          .messageCustomer(orderId: orderId, message: message),
      quickReplies: const [
        'I am outside now.',
        'I am at the gate — please come down.',
        'Running a few minutes late, sorry.',
        'I cannot find the address. Can you call me?',
      ],
    );
    if (sent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message sent')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allDeliveries = ref.watch(activeDeliveriesProvider);
    final orders = allDeliveries.valueOrNull ?? [];
    final order =
        orders.where((o) => o.id == widget.orderId).firstOrNull;

    // If this delivery was completed and is no longer in the list, pop.
    if (allDeliveries.hasValue && order == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }

    final detailAsync =
        ref.watch(activeDeliveryDetailProvider(widget.orderId));

    return Scaffold(
      appBar: UniflexAppBar(
        title: order != null ? 'Delivery ${order.shortId}' : 'Active Delivery',
      ),
      body: allDeliveries.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load this delivery.',
          onRetry: () => ref.invalidate(activeDeliveriesProvider),
        ),
        data: (_) {
          if (order == null) {
            return const Center(child: Text('No active delivery.'));
          }

          final isPicked = order.deliveryStage == 'picked_up';

          return detailAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                _buildBody(context, theme, order, null, isPicked),
            data: (detail) =>
                _buildBody(context, theme, order, detail, isPicked),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    Order liveOrder,
    ActiveDeliveryDetail? detail,
    bool isPicked,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status banner ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: (isPicked ? AppColors.emerald : AppColors.orange)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: (isPicked ? AppColors.emerald : AppColors.orange)
                    .withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isPicked
                      ? Icons.check_circle_outline
                      : Icons.delivery_dining,
                  color: isPicked ? AppColors.emerald : AppColors.orange,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  isPicked
                      ? 'Item picked up — heading to customer'
                      : 'Heading to pickup point',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isPicked ? AppColors.emerald : AppColors.orange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Pickup section ───────────────────────────────────────────
          _SectionCard(
            title: isPicked ? 'Picked Up From' : 'Pickup Point',
            icon: isPicked ? Icons.check : Icons.store_outlined,
            iconColor: isPicked ? AppColors.emerald : AppColors.orange,
            dimmed: isPicked,
            children: [
              Text(
                detail?.pickupName ?? 'Loading…',
                style: theme.textTheme.titleSmall,
              ),
              if (detail?.pickupAddress != null) ...[
                const SizedBox(height: 2),
                Text(
                  detail!.pickupAddress!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (!isPicked && detail?.pickupAddress != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Navigate'),
                  onPressed: () => _navigateTo(detail!.pickupAddress!),
                ),
              ],
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // ── Delivery section ─────────────────────────────────────────
          _SectionCard(
            title: 'Deliver To',
            icon: Icons.location_on_outlined,
            iconColor: theme.colorScheme.primary,
            children: [
              Text(
                liveOrder.deliveryLocation ?? '—',
                style: theme.textTheme.titleSmall,
              ),
              if (isPicked && liveOrder.deliveryLocation != null) ...[
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Navigate'),
                  onPressed: () =>
                      _navigateTo(liveOrder.deliveryLocation!),
                ),
              ],
            ],
          ),

          // ── Customer contact ─────────────────────────────────────────
          const SizedBox(height: AppSpacing.md),
          _SectionCard(
            title: 'Customer',
            icon: Icons.person_outline,
            iconColor: theme.colorScheme.secondary,
            children: [
              if (detail?.customerName != null)
                Text(
                  detail!.customerName!,
                  style: theme.textTheme.labelLarge,
                ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (detail?.customerPhone != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.phone_outlined, size: 16),
                      label: Text(detail!.customerPhone!),
                      onPressed: () => _callCustomer(detail.customerPhone!),
                    )
                  else
                    Text(
                      'No phone number on file.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  // Works whether or not a phone number exists — the student
                  // gets a push plus an entry in their notifications.
                  OutlinedButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 16),
                    label: const Text('Message'),
                    onPressed: () =>
                        _messageCustomer(liveOrder.id, detail?.customerName),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xl),

          // ── Primary action ────────────────────────────────────────────
          if (!isPicked)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isConfirmingPickup ? null : _confirmPickup,
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange),
                child: _isConfirmingPickup
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite,
                        ),
                      )
                    : const Text('Confirm Pickup'),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isVerifying
                    ? null
                    : () => _showPinEntry(detail ??
                        ActiveDeliveryDetail(
                          order: liveOrder,
                          pickupName: '—',
                        )),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.emerald),
                child: _isVerifying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.pureWhite,
                        ),
                      )
                    : const Text('Verify Delivery (Enter PIN)'),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.children,
    this.dimmed = false,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final List<Widget> children;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: dimmed ? 0.5 : 1.0),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...children,
        ],
      ),
    );
  }
}
