/// A named delivery destination with a base price. Admins manage
/// these via `delivery_locations` table; students select one at
/// checkout instead of choosing campus_delivery / hostel_delivery.
class DeliveryLocation {
  const DeliveryLocation({
    required this.id,
    required this.name,
    required this.price,
    required this.isActive,
    required this.sortOrder,
  });

  factory DeliveryLocation.fromMap(Map<String, dynamic> map) {
    return DeliveryLocation(
      id: map['id'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  final String id;
  final String name;
  final double price;
  final bool isActive;
  final int sortOrder;
}
