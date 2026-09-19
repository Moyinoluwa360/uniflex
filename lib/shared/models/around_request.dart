import 'package:flutter/material.dart';

/// The five categories of "Around" (on-demand errand) request. Printing
/// and photocopy requests are explicitly out of scope — they require a
/// separate file-upload / per-page pricing flow.
enum AroundCategory {
  errand,
  laundry,
  hostel,
  vendorFetch,
  peerCourier;

  String get label => switch (this) {
        errand => 'General Errand',
        laundry => 'Laundry Pickup & Dropoff',
        hostel => 'Hostel Transfer',
        vendorFetch => 'Nearby Shop Fetch',
        peerCourier => 'Peer Courier',
      };

  String get description => switch (this) {
        errand =>
          'Free-text description of any item or task you need fetched on or near campus.',
        laundry =>
          'Rider picks up your laundry bag and drops it at the laundry point — or picks it up when ready. No washing service included.',
        hostel =>
          'Move items between hostels or any two campus points.',
        vendorFetch =>
          'Fetch an item from any nearby off-catalog shop or vendor.',
        peerCourier =>
          'Point-to-point delivery from you to another student, or vice versa.',
      };

  IconData get icon => switch (this) {
        errand => Icons.assignment_outlined,
        laundry => Icons.local_laundry_service_outlined,
        hostel => Icons.home_outlined,
        vendorFetch => Icons.storefront_outlined,
        peerCourier => Icons.send_outlined,
      };

  /// Flat estimated fee for this category (₦). Phase 3 will replace
  /// these with dynamic pricing.
  double get estimatedFee => switch (this) {
        errand => 500,
        laundry => 600,
        hostel => 400,
        vendorFetch => 500,
        peerCourier => 400,
      };

  String get rawValue => switch (this) {
        errand => 'errand',
        laundry => 'laundry',
        hostel => 'hostel',
        vendorFetch => 'vendor_fetch',
        peerCourier => 'peer_courier',
      };

  static AroundCategory fromString(String s) {
    return switch (s) {
      'laundry' => laundry,
      'hostel' => hostel,
      'vendor_fetch' => vendorFetch,
      'peer_courier' => peerCourier,
      _ => errand,
    };
  }
}

/// Details of an Around request, stored in `around_requests` and linked
/// 1-to-1 with an `orders` row (which carries the status and amount).
class AroundRequest {
  const AroundRequest({
    required this.id,
    required this.orderId,
    required this.category,
    required this.pickupLocation,
    required this.dropoffLocation,
    required this.itemDescription,
    required this.estimatedFee,
  });

  factory AroundRequest.fromMap(Map<String, dynamic> map) {
    return AroundRequest(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      category: AroundCategory.fromString(map['category'] as String),
      pickupLocation: map['pickup_location'] as String,
      dropoffLocation: map['dropoff_location'] as String,
      itemDescription: map['item_description'] as String,
      estimatedFee: (map['estimated_fee'] as num).toDouble(),
    );
  }

  final String id;
  final String orderId;
  final AroundCategory category;
  final String pickupLocation;
  final String dropoffLocation;
  final String itemDescription;
  final double estimatedFee;
}
