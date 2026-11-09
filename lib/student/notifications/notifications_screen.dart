import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/app_notification.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/async/retry_section.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../../shared/widgets/lists/app_list_group.dart';
import '../../shared/widgets/lists/notification_row.dart';
import 'notification_router.dart';

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
            AppButton(
              label: 'Mark all read',
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              expand: false,
              onPressed: () async {
                try {
                  await ref
                      .read(notificationInboxServiceProvider)
                      .markAllRead();
                  // Re-read from the server so the screen shows what is
                  // really stored (and stays read after reopening).
                  ref.invalidate(notificationInboxProvider);
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Could not mark notifications as read. Please try again.'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                }
              },
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
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.screenGutter),
            children: [
              AppListGroup(
                children: [for (final n in items) _NotificationTile(n)],
              ),
            ],
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
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppIcons.bell, size: 36, color: c.textTertiary),
            const SizedBox(height: AppSpacing.md),
            Text('Nothing yet', style: AppTypography.title(c)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Updates about your orders will appear here.',
              textAlign: TextAlign.center,
              style: AppTypography.meta(c),
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
    return NotificationRow(
      icon: item.type == 'final_price'
          ? AppIcons.receipt
          : item.isFromStatusChange
              ? AppIcons.delivery
              : AppIcons.chat,
      title: item.title,
      body: item.body,
      timeText: _relativeTime(item.createdAt),
      unread: item.isUnread,
      onTap: () => openNotificationTarget(
        context,
        ref,
        NotificationTarget.fromNotification(item),
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
