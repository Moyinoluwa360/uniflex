import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/rider_providers.dart';

/// Multi-stop delivery screen for a delivery group.
/// Shows each vendor stop with per-leg pickup confirmation, then a single
/// PIN entry to complete the whole group delivery.
class GroupDeliveryScreen extends ConsumerStatefulWidget {
  const GroupDeliveryScreen({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<GroupDeliveryScreen> createState() =>
      _GroupDeliveryScreenState();
}

class _GroupDeliveryScreenState extends ConsumerState<GroupDeliveryScreen> {
  bool _isVerifying = false;
  final Map<String, bool> _confirmingLegs = {};

  Future<void> _confirmLegPickup(String orderId) async {
    setState(() => _confirmingLegs[orderId] = true);
    try {
      await ref.read(riderServiceProvider).confirmGroupLegPickup(orderId);
      ref.invalidate(groupLegsProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to confirm pickup: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _confirmingLegs[orderId] = false);
      }
    }
  }

  Future<void> _showPinEntry() async {
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
      await ref
          .read(riderServiceProvider)
          .verifyGroupDelivery(widget.groupId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group delivery completed!')),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
    final legsAsync = ref.watch(groupLegsProvider(widget.groupId));

    return Scaffold(
      appBar: const UniflexAppBar(
        title: 'Group Delivery',
      ),
      body: groupAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RetrySection(
          message: 'Could not load delivery group.',
          onRetry: () {
            ref.invalidate(groupDetailProvider(widget.groupId));
            ref.invalidate(groupLegsProvider(widget.groupId));
          },
        ),
        data: (group) {
          if (group == null) {
            return const Center(child: Text('Delivery group not found.'));
          }

          // If group completed, pop back.
          if (group.isTerminal) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            });
          }

          return legsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => RetrySection(
              message: 'Could not load vendor stops.',
              onRetry: () =>
                  ref.invalidate(groupLegsProvider(widget.groupId)),
            ),
            data: (legs) => _buildBody(context, theme, group, legs),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    DeliveryGroup group,
    List<Order> legs,
  ) {
    final allPickedUp = legs.isNotEmpty &&
        legs.every((l) => l.deliveryStage == 'picked_up');
    final isOutForDelivery =
        group.status == DeliveryGroupStatus.outForDelivery;

    // Determine banner state.
    final Color bannerColor;
    final String bannerText;
    final IconData bannerIcon;

    if (allPickedUp) {
      bannerColor = AppColors.emerald;
      bannerText = 'All items picked up — heading to customer';
      bannerIcon = Icons.check_circle_outline;
    } else if (isOutForDelivery) {
      bannerColor = AppColors.orange;
      bannerText = 'Pick up items from each vendor below';
      bannerIcon = Icons.delivery_dining;
    } else {
      bannerColor = AppColors.info;
      bannerText = group.status.label;
      bannerIcon = Icons.info_outline;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status banner ──────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: bannerColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(bannerIcon, color: bannerColor),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    bannerText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: bannerColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Group info ─────────────────────────────────────────────
          Text(
            'Group ${group.shortId}',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${legs.length} vendor ${legs.length == 1 ? 'stop' : 'stops'} · '
            '${switch (group.deliveryType) {
              'campus_delivery' => 'Campus delivery',
              'hostel_delivery' => 'Hostel delivery',
              _ => 'Delivery',
            }}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),

          const SizedBox(height: AppSpacing.lg),

          // ── Vendor stops ───────────────────────────────────────────
          Text(
            'Vendor Stops',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          ...legs.asMap().entries.map((entry) {
            final index = entry.key;
            final leg = entry.value;
            final isPickedUp = leg.deliveryStage == 'picked_up';
            final isConfirming = _confirmingLegs[leg.id] ?? false;

            return Padding(
              padding: EdgeInsets.only(
                bottom: index < legs.length - 1 ? AppSpacing.cardGap : 0,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: isPickedUp ? 0.5 : 1.0),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: isPickedUp
                      ? Border.all(
                          color: AppColors.emerald.withValues(alpha: 0.4))
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: isPickedUp
                                ? AppColors.emerald.withValues(alpha: 0.15)
                                : theme.colorScheme.primary
                                    .withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isPickedUp
                                ? const Icon(Icons.check,
                                    size: 16, color: AppColors.emerald)
                                : Text(
                                    '${index + 1}',
                                    style:
                                        theme.textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            leg.vendorName ?? 'Vendor ${index + 1}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: isPickedUp
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                        if (isPickedUp)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.emerald.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              'Picked up',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.emerald,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!isPickedUp) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.map_outlined, size: 16),
                              label: const Text('Navigate'),
                              onPressed: leg.vendorName != null
                                  ? () => _navigateTo(leg.vendorName!)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: FilledButton(
                              onPressed:
                                  isConfirming ? null : () => _confirmLegPickup(leg.id),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.orange,
                              ),
                              child: isConfirming
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.pureWhite,
                                      ),
                                    )
                                  : const Text('Confirm Pickup'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: AppSpacing.lg),

          // ── Deliver to ─────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.location_on_outlined,
                        size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      'Deliver To',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  group.deliveryLocation ?? '—',
                  style: theme.textTheme.titleSmall,
                ),
                if (allPickedUp && group.deliveryLocation != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: const Text('Navigate'),
                    onPressed: () => _navigateTo(group.deliveryLocation!),
                  ),
                ],
              ],
            ),
          ),

          // ── Student note ───────────────────────────────────────────
          if (group.studentNote != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sticky_note_2_outlined,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Note from Customer',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    group.studentNote!,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: AppSpacing.xl),

          // ── Primary action ─────────────────────────────────────────
          if (allPickedUp)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isVerifying ? null : _showPinEntry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.emerald,
                ),
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
            )
          else
            SizedBox(
              width: double.infinity,
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AppColors.warning),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Pick up from all vendors before delivering',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
