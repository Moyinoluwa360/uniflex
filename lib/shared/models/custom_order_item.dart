/// A custom item added by a rider during the sourcing phase of a
/// partner/around order. Must be approved or rejected by the student
/// before the rider includes it in the final total.
class CustomOrderItem {
  const CustomOrderItem({
    required this.id,
    required this.orderId,
    required this.description,
    required this.price,
    required this.status,
    required this.addedBy,
    this.decidedAt,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final String description;
  final double price;

  /// 'pending' | 'approved' | 'rejected'
  final String status;
  final String addedBy;
  final DateTime? decidedAt;
  final DateTime createdAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory CustomOrderItem.fromMap(Map<String, dynamic> map) {
    return CustomOrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      description: map['description'] as String,
      price: (map['price'] as num).toDouble(),
      status: map['status'] as String? ?? 'pending',
      addedBy: map['added_by'] as String,
      decidedAt: map['decided_at'] != null
          ? DateTime.parse(map['decided_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
