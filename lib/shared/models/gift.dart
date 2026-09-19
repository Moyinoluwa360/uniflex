/// A row from the `gifts` table, enriched with sender/recipient names.
class Gift {
  const Gift({
    required this.id,
    required this.createdAt,
    required this.direction,
    required this.otherPartyName,
    required this.totalAmount,
    required this.orderStatus,
    this.orderId,
    this.message,
  });

  factory Gift.fromMap(Map<String, dynamic> map) {
    final direction = map['direction'] as String;
    final otherName = direction == 'sent'
        ? (map['recipient_name'] as String? ?? '—')
        : (map['sender_name'] as String? ?? '—');
    return Gift(
      id: map['id'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      direction: direction,
      otherPartyName: otherName,
      totalAmount: (map['total_amount'] as num?)?.toDouble() ?? 0,
      orderStatus: map['order_status'] as String? ?? 'placed',
      orderId: map['order_id'] as String?,
      message: map['message'] as String?,
    );
  }

  final String id;
  final DateTime createdAt;

  /// 'sent' | 'received'
  final String direction;
  final String otherPartyName;
  final double totalAmount;
  final String orderStatus;
  final String? orderId;
  final String? message;

  bool get isSent => direction == 'sent';
}
