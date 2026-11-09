import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'gift_models.dart';
import 'gift_repository.dart';

Color giftStatusColor(String status) => switch (status) {
      'preparing' => AppColors.warning,
      'on_the_way' => AppColors.orange,
      'delivered' => AppColors.emerald,
      'cancelled' => AppColors.error,
      _ => AppColors.info,
    };

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
    final theme = Theme.of(context);
    final color = giftStatusColor(gift.status);
    final pin = gift.deliveryPin;
    final showPin = !gift.isEnded && pin != null && pin.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenGutter),
      children: [
        Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 28)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Gift from ${gift.senderNickname}',
                key: const ValueKey('gift-title'),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                gift.statusLabel,
                key: const ValueKey('gift-status'),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${gift.shortId} · ${formatLocalDateTime(gift.createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (gift.status != 'cancelled') _StatusSteps(status: gift.status),
        if (gift.status == 'cancelled')
          Text(
            'This gift was cancelled.',
            key: const ValueKey('gift-cancelled'),
            style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.error),
          ),
        if (gift.message != null && gift.message!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            key: const ValueKey('gift-message'),
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: Text('“${gift.message!.trim()}”',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontStyle: FontStyle.italic)),
          ),
        ],
        if (showPin) ...[
          const SizedBox(height: AppSpacing.lg),
          _PinCard(pin: pin),
        ],
        if (gift.deliveryLocation != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Delivery to', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  [gift.deliveryLocation, gift.locationDetails]
                      .whereType<String>()
                      .where((e) => e.trim().isNotEmpty)
                      .join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text("What's in it", style: theme.textTheme.titleSmall),
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
    final theme = Theme.of(context);
    final at = GiftReceivedView._steps.indexOf(status).clamp(0, 3);
    return Column(
      children: [
        for (var i = 0; i < GiftReceivedView._steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  i <= at ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 18,
                  color: i <= at
                      ? AppColors.emerald
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  giftStatusLabel(GiftReceivedView._steps[i]),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: i == at ? FontWeight.w700 : FontWeight.w400,
                    color: i <= at
                        ? null
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});
  final String pin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      key: const ValueKey('gift-pin-card'),
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.emerald.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            'Give this PIN to the rider when your food arrives',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.emerald.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: pin));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('PIN copied'),
                behavior: SnackBarBehavior.floating,
              ));
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final digit in pin.split(''))
                  Container(
                    width: 44,
                    height: 52,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.emerald.withValues(alpha: 0.4)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      digit,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
