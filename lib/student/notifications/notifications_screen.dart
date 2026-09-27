import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/app_notification.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../ordering/order_repository.dart';
import '../tracking/order_tracking_screen.dart';

/// The student's notification inbox: automatic order-progress updates plus
/// any message Admin or their rider sent about a specific order.
///
/// Push notifications can be missed or dismissed, so every notification is
/// also recorded server-side and shown here — this list, not the push, is
/// the durable record.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inboxAsync = ref.watch(notificationInboxProvider);
    final hasUnread = ref.watch(unreadNotificationCountProvider) > 0;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Notifications',
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () => ref
                  .read(notificationInboxServiceProvider)
                  .markAllRead(),
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: inboxAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => RetrySection(
          message: 'Could not load your notifications.',
          onRetry: () => ref.invalidate(notificationInboxProvider),
        ),
        data: (items) {
          if (items.isEmpty) return const _EmptyInbox();
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            itemCount: items.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.cardGap),
            itemBuilder: (context, i) => _NotificationTile(items[i]),
          );
        },
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.emerald.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  size: 36, color: AppColors.emerald),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Nothing yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Updates about your orders will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile(this.item);

  final AppNotification item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final unread = item.isUnread;

    return Material(
      color: unread
          ? AppColors.emerald.withValues(alpha: 0.06)
          : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () async {
          if (unread) {
            await ref
                .read(notificationInboxServiceProvider)
                .markRead(item.id);
          }
          final orderId = item.orderId;
          if (orderId == null) return;

          // The tracking screen wants the whole order, and a notification
          // only carries its id — so resolve it first. A null result means
          // the order is gone; stay put rather than pushing an empty screen.
          final order = await ref.read(orderByIdProvider(orderId).future);
          if (order == null || !context.mounted) return;
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OrderTrackingScreen(order: order),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (item.isFromStatusChange
                          ? AppColors.emerald
                          : AppColors.orange)
                      .withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  item.isFromStatusChange
                      ? Icons.local_shipping_outlined
                      : Icons.chat_bubble_outline,
                  size: 18,
                  color: item.isFromStatusChange
                      ? AppColors.emerald
                      : AppColors.orange,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(item.body, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text(
                      _relativeTime(item.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${at.day}/${at.month}/${at.year}';
  }
}
