import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/app_notification.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../gifts/gift_received_screen.dart';
import '../ordering/order_repository.dart';
import '../support/support_chat_screen.dart';
import '../tracking/order_tracking_screen.dart';

/// Where a notification should take the student. Built from either a push
/// payload (`type`, `order_id`, `group_id`, `conversation_id`,
/// `notification_id`) or an inbox row, so both open the same screen.
class NotificationTarget {
  const NotificationTarget({
    this.notificationId,
    this.type,
    this.orderId,
    this.groupId,
    this.conversationId,
  });

  factory NotificationTarget.fromPayload(Map<String, dynamic> data) {
    String? s(String key) {
      final v = data[key];
      if (v == null) return null;
      final str = v.toString();
      return str.isEmpty ? null : str;
    }

    return NotificationTarget(
      notificationId: s('notification_id'),
      type: s('type'),
      orderId: s('order_id'),
      groupId: s('group_id'),
      conversationId: s('conversation_id'),
    );
  }

  factory NotificationTarget.fromNotification(AppNotification n) =>
      NotificationTarget(
        notificationId: n.id,
        type: n.type,
        orderId: n.orderId,
        groupId: n.groupId,
        conversationId: n.conversationId,
      );

  final String? notificationId;
  final String? type;
  final String? orderId;
  final String? groupId;
  final String? conversationId;

  bool get isSupport => type == 'support' || conversationId != null;

  /// gift_received | gift_on_the_way | gift_delivered | gift_cancelled — sent
  /// to the RECIPIENT, who cannot read the sender's order, so these open the
  /// gift view instead of order tracking.
  bool get isGift => (type ?? '').startsWith('gift_');
}

/// Marks the notification read, then opens the right screen: the support
/// chat, the delivery-group tracking screen, or a single order's tracking.
Future<void> openNotificationTarget(
  BuildContext context,
  WidgetRef ref,
  NotificationTarget target,
) async {
  final id = target.notificationId;
  if (id != null) {
    try {
      await ref.read(notificationInboxServiceProvider).markRead(id);
    } catch (_) {
      // Opening the screen matters more than the read marker.
    }
  }
  if (!context.mounted) return;
  final navigator = Navigator.of(context);

  if (target.isSupport) {
    await navigator.push(
      MaterialPageRoute(builder: (_) => const SupportChatScreen()),
    );
    return;
  }

  final groupId = target.groupId;
  if (target.isGift && groupId != null) {
    await navigator.push(
      MaterialPageRoute(builder: (_) => GiftReceivedScreen(groupId: groupId)),
    );
    return;
  }
  if (groupId != null) {
    final group = await ref.read(groupByIdProvider(groupId).future);
    if (group == null || !context.mounted) return;
    await navigator.push(
      MaterialPageRoute(
          builder: (_) => OrderTrackingScreen.forGroup(group: group)),
    );
    return;
  }

  final orderId = target.orderId;
  if (orderId != null) {
    final order = await ref.read(orderByIdProvider(orderId).future);
    // A null order means it is gone; stay put rather than push an empty screen.
    if (order == null || !context.mounted) return;
    await navigator.push(
      MaterialPageRoute(builder: (_) => OrderTrackingScreen(order: order)),
    );
  }
}
