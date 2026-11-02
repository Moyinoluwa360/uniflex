import '../../shared/models/delivery_group.dart';

/// A delivery group visible in the rider job pool — committed but
/// not yet accepted by any rider.
class PoolGroup {
  const PoolGroup({
    required this.group,
    required this.vendorNames,
    required this.legCount,
  });

  final DeliveryGroup group;

  /// Names of the vendors in this delivery group.
  final List<String> vendorNames;

  /// Number of order legs (one per vendor).
  final int legCount;
}
