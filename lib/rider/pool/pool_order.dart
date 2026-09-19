import '../../shared/models/order.dart';

/// An order that is currently visible in the job pool — i.e. unassigned
/// and in a pool-eligible status. Enriches the raw [Order] with pre-fetched
/// pickup information so the pool card can render without extra queries.
class PoolOrder {
  const PoolOrder({
    required this.order,
    required this.pickupName,
    this.pickupAddress,
    required this.orderTypeLabel,
  });

  final Order order;

  /// Human-readable name of the pickup point.
  /// "Uniflex Kitchen" | partner vendor name | "Customer Pickup Point"
  final String pickupName;

  /// Street / campus address of the pickup point, or null when not available
  /// (e.g. Uniflex kitchen — fixed well-known campus location).
  final String? pickupAddress;

  /// Short label for the order source shown as a badge on the pool card.
  /// "Uniflex Food" | "Partner Food" | "Around"
  final String orderTypeLabel;
}
