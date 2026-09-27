import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_notification.dart';
import '../supabase/supabase_providers.dart';

/// Thrown when notifying a customer fails in a way worth showing the sender.
class NotifyException implements Exception {
  NotifyException(this.message);
  final String message;

  @override
  String toString() => 'NotifyException: $message';
}

/// Reads the signed-in student's notification inbox, and — for Admin and
/// Rider — sends notifications about an order.
///
/// Sending always goes through the `notify-user` Edge Function rather than
/// `send-notification` directly: that function checks the sender is allowed
/// to contact this customer and resolves the device token server-side, so
/// push tokens never reach a client.
class NotificationInboxService {
  const NotificationInboxService(this._client);

  final SupabaseClient _client;

  Future<List<AppNotification>> fetch({int limit = 50}) async {
    final rows = await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map((m) => AppNotification.fromMap(m)).toList();
  }

  /// Live inbox for the signed-in user. Realtime is enabled on the table, so
  /// a push that arrives while the app is open updates the list and the bell
  /// badge without a manual refresh.
  Stream<List<AppNotification>> watch() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(const []);
    return _client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((m) => AppNotification.fromMap(m)).toList());
  }

  Future<void> markRead(String id) =>
      _client.rpc('mark_notification_read', params: {'p_id': id});

  Future<void> markAllRead() => _client.rpc('mark_all_notifications_read');

  /// Tells the customer their order moved to its current status. Copy is
  /// generated server-side so every caller says the same thing.
  ///
  /// Deliberately never throws: this is fired after a status change that has
  /// already succeeded, and a failed push must not make the status change
  /// look like it failed. Returns true if something was delivered.
  Future<bool> notifyOrderStatus(String orderId) async {
    try {
      await _client.functions.invoke('notify-user', body: {
        'order_id': orderId,
        'kind': 'order_status',
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends a free-text message to the order's customer. Unlike
  /// [notifyOrderStatus] this is an explicit user action, so failures are
  /// surfaced.
  Future<void> messageCustomer({
    required String orderId,
    required String message,
  }) async {
    try {
      final response = await _client.functions.invoke('notify-user', body: {
        'order_id': orderId,
        'kind': 'message',
        'message': message,
      });
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw NotifyException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final details = e.details;
      throw NotifyException(
        details is Map && details['error'] != null
            ? details['error'].toString()
            : 'Could not send the message.',
      );
    }
  }
}

final notificationInboxServiceProvider =
    Provider<NotificationInboxService>((ref) {
  return NotificationInboxService(ref.watch(supabaseClientProvider));
});

/// Live notification inbox for the signed-in student.
final notificationInboxProvider =
    StreamProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationInboxServiceProvider).watch();
});

/// Unread count, derived from the live inbox so the bell badge and the list
/// can never disagree.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final inbox = ref.watch(notificationInboxProvider);
  return inbox.valueOrNull?.where((n) => n.isUnread).length ?? 0;
});
