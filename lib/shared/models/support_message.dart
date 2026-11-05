/// One message in a support conversation. Written by [send_support_message]
/// RPC — never inserted directly by the client.
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderRole,
    required this.senderName,
    required this.body,
    this.orderId,
    this.deliveryGroupId,
    required this.createdAt,
  });

  factory SupportMessage.fromMap(Map<String, dynamic> m) {
    return SupportMessage(
      id: m['id'] as String,
      conversationId: m['conversation_id'] as String,
      senderId: m['sender_id'] as String,
      senderRole: m['sender_role'] as String,
      senderName: m['sender_name'] as String,
      body: m['body'] as String,
      orderId: m['order_id'] as String?,
      deliveryGroupId: m['delivery_group_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String).toLocal(),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;

  /// 'student' | 'admin'
  final String senderRole;

  /// Snapshot of the sender's name at send time. Admin messages show the
  /// individual admin's name; student messages show their nickname.
  final String senderName;
  final String body;

  /// Non-null when the student attached a standalone order to this message.
  final String? orderId;

  /// Non-null when the student attached a delivery group to this message.
  final String? deliveryGroupId;
  final DateTime createdAt;

  bool get isFromAdmin => senderRole == 'admin';
  bool get isFromStudent => senderRole == 'student';
}
