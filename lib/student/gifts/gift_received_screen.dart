import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/order_breakdown/order_breakdown_widget.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/tracking/pin_digit_boxes.dart';
import '../../shared/widgets/tracking/tracking_stepper.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/text/app_section_label.dart';
import 'gift_models.dart';
import 'gift_repository.dart';

/// A gift the signed-in student RECEIVES: live status, the sender's message,
/// what is in it (no prices) and the delivery PIN. Read-only — there is
/// nothing to pay, decline, cancel or edit, so there are no such buttons.
class GiftReceivedScreen extends ConsumerWidget {
  const GiftReceivedScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivedGiftByGroupProvider(groupId));
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Gift'),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => RetrySection(
          message: 'Could not load this gift.',
          onRetry: () => ref.invalidate(receivedGiftsProvider),
        ),
        data: (gift) => gift == null
            ? const Center(child: Text('This gift is not available.'))
            : GiftReceivedView(gift: gift),
      ),
    );
  }
}

/// Pure rendering of a received gift (what the widget tests drive).
class GiftReceivedView extends StatelessWidget {
  const GiftReceivedView({super.key, required this.gift});

  final GiftDelivery gift;

  static const _steps = ['placed', 'preparing', 'on_the_way', 'delivered'];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = StatusPresenter.gift(gift.status);
    final pin = gift.deliveryPin;
    final showPin = !gift.isEnded && pin != null && pin.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Row(
          children: [
            Icon(AppIcons.gift, size: 28, color: c.textSecondary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Gift from ${gift.senderNickname}',
                key: const ValueKey('gift-title'),
                style: AppTypography.title(c),
              ),
            ),
            KeyedSubtree(
              key: const ValueKey('gift-status'),
              child: AppStatusLabel(tone: status.tone, text: gift.statusLabel),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${gift.shortId} · ${formatLocalDateTime(gift.createdAt)}',
          style: AppTypography.caption(c),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (gift.status != 'cancelled') _StatusSteps(status: gift.status),
        if (gift.status == 'cancelled')
          Text(
            'This gift was cancelled.',
            key: const ValueKey('gift-cancelled'),
            style: AppTypography.body(c).copyWith(color: c.dangerText),
          ),
        if (gift.message != null && gift.message!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            key: const ValueKey('gift-message'),
            width: double.infinity,
            child: AppCard(
              child: Text('“${gift.message!.trim()}”',
                  style: AppTypography.body(c)
                      .copyWith(fontStyle: FontStyle.italic)),
            ),
          ),
        ],
        if (showPin) ...[
          const SizedBox(height: AppSpacing.lg),
          _PinCard(pin: pin),
        ],
        if (gift.deliveryLocation != null) ...[
          const SizedBox(height: AppSpacing.lg),
          const AppSectionLabel('Delivery to'),
          const SizedBox(height: AppSpacing.sm),
          AppListGroup(
            children: [
              AppListRow(
                leadingIcon: AppIcons.location,
                title: [gift.deliveryLocation, gift.locationDetails]
                    .whereType<String>()
                    .where((e) => e.trim().isNotEmpty)
                    .join(' · '),
                showChevron: false,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        const AppSectionLabel("What's in it"),
        const SizedBox(height: AppSpacing.md),
        // "No prices" mode: nothing about money is ever drawn here.
        OrderBreakdownView(data: gift.items, showPrices: false),
        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _StatusSteps extends StatelessWidget {
  const _StatusSteps({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final at = GiftReceivedView._steps.indexOf(status).clamp(0, 3);
    final last = GiftReceivedView._steps.length - 1;
    return TrackingStepper(
      labels: [
        for (final s in GiftReceivedView._steps) giftStatusLabel(s),
      ],
      states: [
        for (var i = 0; i < GiftReceivedView._steps.length; i++)
          i > at
              ? TrackingStepState.upcoming
              : (i == at && at != last)
                  ? TrackingStepState.current
                  : TrackingStepState.done,
      ],
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});
  final String pin;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      key: const ValueKey('gift-pin-card'),
      width: double.infinity,
      child: AppCard(
        child: Column(
          children: [
            Text(
              'Give this PIN to the rider when your food arrives',
              style: AppTypography.meta(c),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            PinDigitBoxes(pin: pin),
          ],
        ),
      ),
    );
  }
}

/// A received gift as one row in a list (Orders area and Gifts screen).
class GiftReceivedCard extends StatelessWidget {
  const GiftReceivedCard({super.key, required this.gift, this.onTap});

  final GiftDelivery gift;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = StatusPresenter.gift(gift.status);
    return AppCard(
      onTap: onTap ??
          () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GiftReceivedScreen(groupId: gift.groupId))),
      child: Row(
        children: [
          Icon(AppIcons.gift, size: 24, color: c.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gift from ${gift.senderNickname}',
                    style: AppTypography.body(c)
                        .copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  '${gift.shortId} · ${formatLocalRelative(gift.createdAt)}',
                  style: AppTypography.caption(c),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppStatusLabel(tone: status.tone, text: gift.statusLabel),
        ],
      ),
    );
  }
}
