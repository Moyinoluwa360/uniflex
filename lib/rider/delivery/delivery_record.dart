/// A row from `delivery_records`, enriched with a subset of order fields
/// fetched in the same query. Used exclusively by the history screen.
class DeliveryRecord {
  const DeliveryRecord({
    required this.id,
    required this.orderId,
    required this.completedAt,
    this.durationSeconds,
    this.distanceMeters,
    this.rating,
    this.orderTotal,
    this.orderType,
    this.vendorName,
    this.deliveryLocation,
  });

  factory DeliveryRecord.fromMap(
    Map<String, dynamic> m, [
    Map<String, dynamic>? orderMap,
  ]) {
    return DeliveryRecord(
      id: m['id'] as String,
      orderId: m['order_id'] as String,
      completedAt: DateTime.parse(m['completed_at'] as String),
      durationSeconds: m['duration_seconds'] as int?,
      distanceMeters: m['distance_meters'] as int?,
      rating: m['rating'] as int?,
      orderTotal: orderMap != null
          ? (orderMap['total_amount'] as num?)?.toDouble()
          : null,
      orderType: orderMap?['type'] as String?,
      vendorName: orderMap?['vendors'] != null
          ? (orderMap!['vendors'] as Map<String, dynamic>)['name'] as String?
          : null,
      deliveryLocation: orderMap?['delivery_location'] as String?,
    );
  }

  final String id;
  final String orderId;
  final DateTime completedAt;
  final int? durationSeconds;
  final int? distanceMeters;
  final int? rating;

  // Denormalised order fields (populated when fetched with a join).
  final double? orderTotal;
  final String? orderType;
  final String? vendorName;
  final String? deliveryLocation;

  String get shortId => '#${orderId.substring(0, 8).toUpperCase()}';

  String get durationLabel {
    if (durationSeconds == null) return '—';
    final min = durationSeconds! ~/ 60;
    return min < 1 ? '<1 min' : '$min min';
  }
}
