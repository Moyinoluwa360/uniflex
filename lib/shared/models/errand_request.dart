/// Details of an Errand request, stored in `errand_requests` and linked
/// 1-to-1 with an `orders` row (which carries the status and amount).
///
/// [category] is the `errand_categories.key` foreign key — a plain string
/// rather than a closed enum, since Admin can add new categories at any
/// time from the Manage hub.
class ErrandRequest {
  const ErrandRequest({
    required this.id,
    required this.orderId,
    required this.category,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.itemDescription,
    required this.estimatedFee,
  });

  factory ErrandRequest.fromMap(Map<String, dynamic> map) {
    return ErrandRequest(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      category: map['category'] as String,
      pickupLocation: map['pickup_location'] as String,
      dropoffLocation: map['dropoff_location'] as String,
      itemDescription: map['item_description'] as String,
      estimatedFee: (map['estimated_fee'] as num).toDouble(),
    );
  }

  final String id;
  final String orderId;
  final String category;
  final String pickupLocation;
  final String dropoffLocation;
  final String itemDescription;
  final double estimatedFee;
}
