/// An entry in the student's notification inbox. Written server-side by the
/// `notify-user` Edge Function — either automatically from an order status
/// change, or as a free-text message from Admin or the assigned Rider.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    required this.createdAt,
    this.orderId,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      kind: map['kind'] as String? ?? 'message',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      orderId: map['order_id'] as String?,
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
  final DateTime createdAt;
  final String? orderId;
  final DateTime? readAt;

  bool get isUnread => readAt == null;
  bool get isFromStatusChange => kind == 'order_status';
}
