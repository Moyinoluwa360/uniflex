import 'order_item.dart';

/// Status of an order, mirroring the `status` check constraint on the
/// `orders` table. The tracking screen uses this to render the status
/// timeline; the data source can be swapped for a Supabase realtime
/// stream in Phase 3 without changing the UI.
enum OrderStatus {
  placed,
  preparing,
  ready,
  outForDelivery,
  readyForPickup,
  completed,
  cancelled;

  static OrderStatus fromString(String s) {
    return switch (s) {
      'preparing' => preparing,
      'ready' => ready,
      'out_for_delivery' => outForDelivery,
      'ready_for_pickup' => readyForPickup,
      'completed' => completed,
      'cancelled' => cancelled,
      _ => placed,
    };
  }

  String get rawValue => switch (this) {
        placed => 'placed',
        preparing => 'preparing',
        ready => 'ready',
        outForDelivery => 'out_for_delivery',
        readyForPickup => 'ready_for_pickup',
        completed => 'completed',
        cancelled => 'cancelled',
      };

  String get label => switch (this) {
        placed => 'Order Placed',
        preparing => 'Preparing',
        ready => 'Ready',
        outForDelivery => 'Out for Delivery',
        readyForPickup => 'Ready for Pickup',
        completed => 'Completed',
        cancelled => 'Cancelled',
      };

  bool get isTerminal => this == completed || this == cancelled;
}

/// A row from the `orders` table. [items] is populated by the order
/// repository when a full order detail is fetched (tracking screen).
/// The list tab fetch leaves [items] empty for performance.
class Order {
  const Order({
    required this.id,
    required this.studentId,
    required this.status,
    required this.source,
    required this.type,
    required this.totalAmount,
    required this.createdAt,
    this.vendorId,
    this.vendorName,
    this.deliveryType,
    this.deliveryLocation,
    this.estimatedTime,
    this.notes,
    this.riderId,
    this.deliveryPin,
    this.deliveryStage,
    this.scheduledFor,
    this.isBulk = false,
    this.bulkDiscountPct = 0,
    this.groupOrderId,
    this.items = const [],
  });

  factory Order.fromMap(Map<String, dynamic> map) {
    return Order(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      status: OrderStatus.fromString(map['status'] as String),
      source: map['source'] as String,
      type: map['type'] as String,
      totalAmount: (map['total_amount'] as num).toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
      vendorId: map['vendor_id'] as String?,
      vendorName: map['vendors'] != null
          ? (map['vendors'] as Map<String, dynamic>)['name'] as String?
          : null,
      deliveryType: map['delivery_type'] as String?,
      deliveryLocation: map['delivery_location'] as String?,
      estimatedTime: map['estimated_time'] as String?,
      notes: map['notes'] as String?,
      riderId: map['rider_id'] as String?,
      deliveryPin: map['delivery_pin'] as String?,
      deliveryStage: map['delivery_stage'] as String?,
      scheduledFor: map['scheduled_for'] == null
          ? null
          : DateTime.parse(map['scheduled_for'] as String),
      isBulk: map['is_bulk'] as bool? ?? false,
      bulkDiscountPct: (map['bulk_discount_pct'] as num?)?.toDouble() ?? 0,
      groupOrderId: map['group_order_id'] as String?,
    );
  }

  final String id;
  final String studentId;
  final OrderStatus status;

  /// 'uniflex' | 'partner' — set at placement time from which vendor
  /// the student ordered from.
  final String source;

  /// 'food' | 'around'
  final String type;

  final double totalAmount;
  final DateTime createdAt;
  final String? vendorId;
  final String? vendorName;

  /// 'pickup' | 'delivery' — only set for food orders.
  final String? deliveryType;
  final String? deliveryLocation;
  final String? estimatedTime;
  final String? notes;

  /// Phase 5: rider assignment and delivery workflow.
  final String? riderId;

  /// One-time delivery PIN (4 chars). Set on INSERT by DB trigger for
  /// delivery-type orders. Shown to student; entered by rider at doorstep.
  final String? deliveryPin;

  /// 'accepted' | 'picked_up' | null. Tracks rider's sub-status within
  /// out_for_delivery. Null when no rider is assigned.
  final String? deliveryStage;

  /// Phase 6: scheduled delivery date/time (null = ASAP).
  final DateTime? scheduledFor;

  /// Phase 6: bulk delivery flag and discount applied.
  final bool isBulk;
  final double bulkDiscountPct;

  /// Phase 6: group order session this order belongs to (null if standalone).
  final String? groupOrderId;

  /// Populated only when the full order detail is fetched.
  final List<OrderItem> items;

  /// Short display reference, e.g. "#A1B2C3D4".
  String get shortId => '#${id.substring(0, 8).toUpperCase()}';

  bool get isFood => type == 'food';
  bool get isAround => type == 'around';
  bool get isForDelivery => deliveryType == 'delivery' ||
      deliveryType == 'campus_delivery' ||
      deliveryType == 'hostel_delivery';
  bool get isScheduled => scheduledFor != null;

  Order copyWith({
    OrderStatus? status,
    String? deliveryStage,
    List<OrderItem>? items,
  }) {
    return Order(
      id: id,
      studentId: studentId,
      status: status ?? this.status,
      source: source,
      type: type,
      totalAmount: totalAmount,
      createdAt: createdAt,
      vendorId: vendorId,
      vendorName: vendorName,
      deliveryType: deliveryType,
      deliveryLocation: deliveryLocation,
      estimatedTime: estimatedTime,
      notes: notes,
      riderId: riderId,
      deliveryPin: deliveryPin,
      deliveryStage: deliveryStage ?? this.deliveryStage,
      scheduledFor: scheduledFor,
      isBulk: isBulk,
      bulkDiscountPct: bulkDiscountPct,
      groupOrderId: groupOrderId,
      items: items ?? this.items,
    );
  }
}
