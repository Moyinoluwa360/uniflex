/// An entry in the user's notification inbox. Written server-side by
/// database triggers (order events, support messages) and by the
/// `notify-user` Edge Function (free-text messages from Admin / a rider).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.type,
    this.orderId,
    this.groupId,
    this.conversationId,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      kind: map['kind'] as String? ?? 'message',
      type: map['type'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      orderId: map['order_id'] as String?,
      groupId: map['group_id'] as String?,
      conversationId: map['conversation_id'] as String?,
      readAt: map['read_at'] == null
          ? null
          : DateTime.parse(map['read_at'] as String).toLocal(),
    );
  }

  final String id;
  final String title;
  final String body;

  /// 'order_status' | 'message'
  final String kind;

  /// Fine-grained event: 'rider_accepted' | 'final_price' | 'customer_paid'
  /// | 'cancelled_by_customer' | 'cancelled_by_admin' | 'delivered'
  /// | 'ready_for_pickup' | 'support' | null (older rows).
  final String? type;
  final DateTime createdAt;
  final String? orderId;
  final String? groupId;
  final String? conversationId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
  bool get isFromStatusChange => kind == 'order_status';
  bool get isSupport => type == 'support';
}
