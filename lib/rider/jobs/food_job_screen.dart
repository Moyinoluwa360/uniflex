import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/order_breakdown/order_breakdown_widget.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/utils/app_error_mapper.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../services/rider_providers.dart';
import '../services/rider_service.dart';
import 'delivery_complete_screen.dart';
import 'rider_job.dart';
import '../../shared/widgets/inputs/app_text_field.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/widgets/format/money.dart';

class FoodJobScreen extends ConsumerStatefulWidget {
  /// Open in preview mode (from the pool — not yet accepted).
  FoodJobScreen.fromPool({super.key, required RiderJob job})
      : groupId = job.id,
        previewJob = job,
        isPreview = true;

  /// Open as an active job (already accepted by this rider).
  const FoodJobScreen.active({super.key, required this.groupId})
      : previewJob = null,
        isPreview = false;

  final String groupId;
  final RiderJob? previewJob;
  final bool isPreview;

  @override
  ConsumerState<FoodJobScreen> createState() => _FoodJobScreenState();
}

class _FoodJobScreenState extends ConsumerState<FoodJobScreen> {
  bool _isAccepting = false;

  Future<void> _accept() async {
    setState(() => _isAccepting = true);
    try {
      await ref.read(riderServiceProvider).acceptDeliveryGroup(widget.groupId);
      ref.invalidate(riderStatsProvider);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => FoodJobScreen.active(groupId: widget.groupId),
          ),
        );
      }
    } catch (e) {
      debugPrint('[FoodJob] accept failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _showEnterPriceSheet({bool isCorrection = false}) async {
    final customerAsync = ref.read(groupCustomerInfoProvider(widget.groupId));
    final customerName =
        customerAsync.valueOrNull?.displayName ?? 'the customer';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _EnterPriceSheet(
        groupId: widget.groupId,
        customerName: customerName,
        isCorrection: isCorrection,
      ),
    );
  }

  Future<void> _showDeliveryPinSheet() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => _DeliveryPinSheet(groupId: widget.groupId),
    );
    if (ok == true && mounted) {
      // Server stamped completed_at; show the summary instead of vanishing.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DeliveryCompleteScreen(jobId: widget.groupId),
        ),
      );
    }
  }

  Widget _itemsSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Order items',
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: AppSpacing.sm),
        OrderBreakdown(orderId: widget.groupId),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!widget.isPreview) {
      final groupAsync = ref.watch(groupDetailProvider(widget.groupId));
      final customerAsync =
          ref.watch(groupCustomerInfoProvider(widget.groupId));

      return Scaffold(
        appBar: UniflexAppBar(
          title: 'Active Job',
          actions: [_FoodBadgeChip()],
        ),
        body: groupAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) {
            debugPrint('[FoodJob] group load error: $e');
            return RetrySection(
              message: 'Could not load job details.',
              onRetry: () =>
                  ref.invalidate(groupDetailProvider(widget.groupId)),
            );
          },
          data: (g) {
            if (g == null) {
              return _NotFoundView(onBack: () => Navigator.of(context).pop());
            }

            // Cancelled by the student after the final price was sent.
            if (g.status == DeliveryGroupStatus.cancelled &&
                g.cancelledByStudent) {
              return _CancelledByStudentView(
                onBack: () => Navigator.of(context).pop(),
              );
            }

            return Column(
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
                      _StatusStepper(status: g.status),
                      const SizedBox(height: AppSpacing.lg),
                      _InfoCard(
                        icon: Icons.tag,
                        label: 'Order ID',
                        value: '#${g.id.substring(0, 8).toUpperCase()}',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      customerAsync.when(
                        loading: () => const _CustomerCardShimmer(),
                        error: (e, _) => RetrySection(
                          message: 'Could not load customer info.',
                          compact: true,
                          onRetry: () => ref.invalidate(
                              groupCustomerInfoProvider(widget.groupId)),
                        ),
                        data: (info) => RiderCustomerCard(info: info),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _itemsSection(theme),
                      const SizedBox(height: AppSpacing.md),
                      _InfoCard(
                        icon: Icons.location_on_outlined,
                        label: 'Drop-off',
                        value: g.deliveryLocation ?? '—',
                      ),
                      if (g.studentNote != null &&
                          g.studentNote!.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        _InfoCard(
                          icon: Icons.sticky_note_2_outlined,
                          label: 'Note from customer',
                          value: g.studentNote!,
                        ),
                      ],
                    ],
                  ),
                ),
                _BottomActionBar(
                  status: g.status,
                  onEnterPrice: () => _showEnterPriceSheet(),
                  onCorrectPrice: () =>
                      _showEnterPriceSheet(isCorrection: true),
                  onEnterPin: _showDeliveryPinSheet,
                ),
              ],
            );
          },
        ),
      );
    }

    // ── Preview mode (from the pool) ──────────────────────────────────
    final job = widget.previewJob!;
    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Job Details',
        actions: [_FoodBadgeChip()],
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
                if (job.isGift) ...[
                  const _InfoCard(
                    icon: Icons.card_giftcard_outlined,
                    label: 'GIFT',
                    value: 'Paid by one student, delivered to another. '
                        'You see both contacts after you accept.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                _itemsSection(theme),
                const SizedBox(height: AppSpacing.md),
                _InfoCard(
                  icon: Icons.location_on_outlined,
                  label: 'Drop-off',
                  value: job.deliveryLocation ?? '—',
                ),
                if (job.studentNote != null &&
                    job.studentNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _InfoCard(
                    icon: Icons.sticky_note_2_outlined,
                    label: 'Note',
                    value: job.studentNote!,
                  ),
                ],
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
            child: AppButton(
              label: 'Accept Job',
              isLoading: _isAccepting,
              onPressed: _isAccepting ? null : _accept,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of an endless spinner when the job cannot be found.
class _NotFoundView extends StatelessWidget {
  const _NotFoundView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 40,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: AppSpacing.md),
            Text('This job is no longer available.',
                style: theme.textTheme.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Go back',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

// ── FOOD badge chip ───────────────────────────────────────────────────────────

class _FoodBadgeChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.md),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: context.colors.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          'FOOD',
          style: theme.textTheme.labelSmall?.copyWith(
            color: context.colors.brandText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Status stepper ────────────────────────────────────────────────────────────

class _StatusStepper extends StatelessWidget {
  const _StatusStepper({required this.status});

  final DeliveryGroupStatus status;

  static const _steps = [
    'Accepted',
    'Price Sent',
    'Awaiting Payment',
    'Out for Delivery',
  ];

  int get _currentStep => switch (status) {
        DeliveryGroupStatus.riderAccepted => 0,
        DeliveryGroupStatus.awaitingFinalPayment => 1,
        DeliveryGroupStatus.outForDelivery => 3,
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentStep;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.colors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line.
            final stepIndex = i ~/ 2;
            final isActive = stepIndex < current;
            return Expanded(
              child: Container(
                height: 2,
                color: isActive
                    ? context.colors.brandText
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
                      ? context.colors.brandText
                      : theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
                child: Center(
                  child: isDone
                      ? Icon(Icons.check,
                          size: 14, color: context.colors.onBrand)
                      : isCurrent
                          ? SizedBox(
                              width: 8,
                              height: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: context.colors.onBrand,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 60,
                child: Text(
                  _steps[stepIndex],
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: isDone || isCurrent
                        ? context.colors.brandText
                        : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                    fontSize: 10,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

/// The accepted rider's view of who they are serving. A gift shows two
/// cards ("Deliver to" + "Paid by"), each with Call and WhatsApp.
class RiderCustomerCard extends StatelessWidget {
  const RiderCustomerCard({super.key, required this.info});

  final GroupCustomerInfo info;

  @override
  Widget build(BuildContext context) {
    if (!info.isGift) {
      return _ContactCard(
        label: 'Customer',
        fullName: info.fullName,
        nickname: info.nickname,
        email: info.email,
        locationDetails: info.locationDetails,
        phone: info.phone,
      );
    }
    // Gift: the food goes to the recipient, the sender paid. Both can be
    // contacted (rider already accepted — the server refuses before that).
    final to = info.giftRecipient!;
    final by = info.giftSender;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContactCard(
          key: const ValueKey('deliver-to-card'),
          label: 'Deliver to',
          fullName: to.fullName,
          nickname: to.nickname,
          email: to.email,
          locationDetails: to.locationDetails ?? info.locationDetails,
          phone: to.phone,
        ),
        if (by != null) ...[
          const SizedBox(height: AppSpacing.md),
          _ContactCard(
            key: const ValueKey('paid-by-card'),
            label: 'Paid by',
            fullName: by.fullName,
            nickname: by.nickname,
            email: by.email,
            phone: by.phone,
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Text(
          'This is a gift. Ask ${to.nickname ?? to.fullName} for the '
          'delivery PIN when you hand over the food.',
          key: const ValueKey('gift-pin-note'),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    super.key,
    required this.label,
    required this.fullName,
    this.nickname,
    this.email,
    this.locationDetails,
    this.phone = '',
  });

  final String label;
  final String fullName;
  final String? nickname;
  final String? email;
  final String? locationDetails;
  final String phone;

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
              Icon(Icons.person_outline,
                  size: 16, color: context.colors.brandText),
              const SizedBox(width: AppSpacing.sm),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: context.colors.brandText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            fullName,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (nickname != null) ...[
            const SizedBox(height: 2),
            Text(
              '@$nickname',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (email != null) ...[
            const SizedBox(height: 2),
            Text(
              email!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (locationDetails != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    locationDetails!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (phone.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: 'Call',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    icon: AppIcons.phone,
                    onPressed: () => _callPhone(context, phone),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: AppButton(
                    label: 'WhatsApp',
                    variant: AppButtonVariant.secondary,
                    size: AppButtonSize.small,
                    icon: AppIcons.chat,
                    onPressed: () => _openWhatsApp(context, phone),
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

class _CustomerCardShimmer extends StatelessWidget {
  const _CustomerCardShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
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

// ── Bottom action bar (active job) ────────────────────────────────────────────

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.status,
    required this.onEnterPrice,
    required this.onCorrectPrice,
    required this.onEnterPin,
  });

  final DeliveryGroupStatus status;
  final VoidCallback onEnterPrice;
  final VoidCallback onCorrectPrice;
  final VoidCallback onEnterPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenGutter,
        AppSpacing.sm,
        AppSpacing.screenGutter,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: switch (status) {
        DeliveryGroupStatus.riderAccepted => SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: AppButton(
              label: 'Enter Final Price',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onEnterPrice,
            ),
          ),
        DeliveryGroupStatus.awaitingFinalPayment => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: context.colors.surfaceRaised,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: context.colors.surfaceRaised),
                ),
                child: Row(
                  children: [
                    Icon(Icons.hourglass_empty,
                        color: context.colors.statusAmber, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Waiting for customer payment...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: context.colors.statusAmber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Correct Price',
                variant: AppButtonVariant.text,
                size: AppButtonSize.small,
                expand: false,
                onPressed: onCorrectPrice,
              ),
            ],
          ),
        DeliveryGroupStatus.outForDelivery => SizedBox(
            width: double.infinity,
            height: AppSpacing.controlHeight,
            child: AppButton(
              label: 'Enter Delivery PIN',
              variant: AppButtonVariant.primary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onEnterPin,
            ),
          ),
        DeliveryGroupStatus.completed => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    color: context.colors.brandText),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Delivery completed',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.colors.brandText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        DeliveryGroupStatus.cancelled => Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: context.colors.surfaceRaised,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.cancel_outlined, color: context.colors.dangerText),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Order cancelled',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: context.colors.dangerText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

// ── Cancelled by student view ─────────────────────────────────────────────────

class _CancelledByStudentView extends StatelessWidget {
  const _CancelledByStudentView({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: context.colors.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cancel_outlined,
                  color: context.colors.dangerText, size: 36),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Cancelled by customer',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This order was declined after you sent the final price.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppButton(
              label: 'Back to jobs',
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.small,
              expand: false,
              onPressed: onBack,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Enter Price bottom sheet ──────────────────────────────────────────────────

class _EnterPriceSheet extends ConsumerStatefulWidget {
  const _EnterPriceSheet({
    required this.groupId,
    required this.customerName,
    this.isCorrection = false,
  });

  final String groupId;
  final String customerName;
  final bool isCorrection;

  @override
  ConsumerState<_EnterPriceSheet> createState() => _EnterPriceSheetState();
}

class _EnterPriceSheetState extends ConsumerState<_EnterPriceSheet> {
  final _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final amountText = _controller.text.trim();
    final amount = double.tryParse(amountText);

    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    if (amount > 500000) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount cannot exceed ₦500,000.')),
      );
      return;
    }

    // Confirmation dialog.
    final confirmed = await AppDialog.show(
      context,
      title: 'Confirm price',
      body:
          'Send ${Money.format(amount)} to ${widget.customerName}?\n\nThey will be asked to pay.',
      secondaryLabel: 'Cancel',
      confirmLabel: 'Send',
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSending = true);
    try {
      await ref
          .read(riderServiceProvider)
          .setGroupFinalPrice(widget.groupId, amount);
      ref.invalidate(groupDetailProvider(widget.groupId));
      ref.invalidate(groupCustomerInfoProvider(widget.groupId));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorMapper.map(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
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
            widget.isCorrection ? 'Correct price' : 'Enter final price',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Enter the total amount you paid across all vendors.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(
              prefixText: '₦ ',
              hintText: '0',
              counterText: '',
            ),
            style: theme.textTheme.headlineMedium,
            autofocus: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Send to customer',
            isLoading: _isSending,
            onPressed: _isSending ? null : _send,
          ),
        ],
      ),
    );
  }
}

// ── Delivery PIN bottom sheet ─────────────────────────────────────────────────

class _DeliveryPinSheet extends ConsumerStatefulWidget {
  const _DeliveryPinSheet({required this.groupId});

  final String groupId;

  @override
  ConsumerState<_DeliveryPinSheet> createState() => _DeliveryPinSheetState();
}

class _DeliveryPinSheetState extends ConsumerState<_DeliveryPinSheet> {
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
        const SnackBar(content: Text('Please enter a 4-character PIN.')),
      );
      return;
    }

    setState(() => _isConfirming = true);
    try {
      await ref
          .read(riderServiceProvider)
          .verifyGroupDelivery(widget.groupId, pin);
      ref.invalidate(riderStatsProvider);
      if (mounted) Navigator.of(context).pop(true); // job screen shows summary
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
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
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
                  selection: TextSelection.collapsed(offset: upper.length),
                );
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: 'Confirm delivery',
            isLoading: _isConfirming,
            onPressed: _isConfirming ? null : _confirm,
          ),
        ],
      ),
    );
  }
}
