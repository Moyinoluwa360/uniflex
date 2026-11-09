import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/utils/local_time.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/cards/app_card.dart';
import '../../shared/widgets/status/app_status_label.dart';
import '../../shared/widgets/status/status_presentation.dart';
import '../../shared/widgets/tabs/app_segmented_tabs.dart';
import '../ordering/order_repository.dart';
import '../tracking/order_tracking_screen.dart';
import 'gift_received_screen.dart';
import 'gift_repository.dart';

/// Profile → Gifts. Two tabs: gifts you SENT (with the recipient's nickname
/// and live status; tap opens your order) and gifts you RECEIVED (tap opens
/// the gift). Gifts are sent from checkout ("Send as a gift"), not here.
class GiftsScreen extends ConsumerWidget {
  const GiftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Gifts')),
        body: Column(
          children: [
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenGutter,
                  AppSpacing.sm,
                  AppSpacing.screenGutter,
                  AppSpacing.sm,
                ),
                child: AppSegmentedTabs(
                  labels: const ['Sent', 'Received'],
                  controller: DefaultTabController.of(context),
                ),
              ),
            ),
            const Expanded(
              child: TabBarView(children: [_SentTab(), _ReceivedTab()]),
            ),
          ],
        ),
      ),
    );
  }
}

class _SentTab extends ConsumerWidget {
  const _SentTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(studentDeliveryGroupsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => RetrySection(
        message: 'Could not load your gifts.',
        onRetry: () => ref.invalidate(studentDeliveryGroupsProvider),
      ),
      data: (groups) {
        final sent = groups.where((g) => g.isGift).toList();
        if (sent.isEmpty) {
          return const _Empty(
            title: 'No gifts sent yet',
            subtitle: 'At checkout, switch on “Send as a gift” to treat '
                'another student.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          itemCount: sent.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (_, i) => SentGiftCard(group: sent[i]),
        );
      },
    );
  }
}

class _ReceivedTab extends ConsumerWidget {
  const _ReceivedTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(receivedGiftsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => RetrySection(
        message: 'Could not load your gifts.',
        onRetry: () => ref.invalidate(receivedGiftsProvider),
      ),
      data: (gifts) {
        if (gifts.isEmpty) {
          return const _Empty(
            title: 'No gifts received yet',
            subtitle: 'When another student sends you food, it shows up here.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          itemCount: gifts.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.cardGap),
          itemBuilder: (_, i) => GiftReceivedCard(gift: gifts[i]),
        );
      },
    );
  }
}

/// A gift I sent: the recipient's nickname and the order's live status.
class SentGiftCard extends StatelessWidget {
  const SentGiftCard({super.key, required this.group, this.onTap});

  final DeliveryGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    final status = StatusPresenter.group(group.status);
    return AppCard(
      onTap: onTap ??
          () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => OrderTrackingScreen.forGroup(group: group))),
      child: Row(
        children: [
          Icon(AppIcons.gift, size: 22, color: c.textSecondary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('To ${group.giftRecipientNickname ?? 'a student'}',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  '${group.shortId} · ${formatLocalRelative(group.createdAt)}',
                  style: AppTypography.caption(c),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppStatusLabel(tone: status.tone, text: status.label),
          Icon(AppIcons.chevronRight, size: 20, color: c.textTertiary),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.subtitle});
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.gift, size: 40, color: c.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.meta(c),
            ),
          ],
        ),
      ),
    );
  }
}
