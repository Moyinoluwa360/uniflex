/// Round 7: A parent record for multi-vendor checkouts.
///
/// One [DeliveryGroup] per checkout, even for single-vendor orders.
/// Each vendor's portion becomes a leg (an `orders` row linked via
/// `delivery_group_id`).
class DeliveryGroup {
  const DeliveryGroup({
    required this.id,
    required this.studentId,
    required this.deliveryType,
    this.deliveryLocation,
    this.studentNote,
    required this.commitmentFeeTotal,
    this.finalAmount,
    required this.finalPaymentPaid,
    required this.status,
    this.riderId,
    this.deliveryPin,
    this.deliveryStage,
    this.scheduledFor,
    required this.createdAt,
  });

  factory DeliveryGroup.fromMap(Map<String, dynamic> map) {
    return DeliveryGroup(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      deliveryType: map['delivery_type'] as String,
      deliveryLocation: map['delivery_location'] as String?,
      studentNote: map['student_note'] as String?,
      commitmentFeeTotal:
          (map['commitment_fee_total'] as num?)?.toDouble() ?? 0,
      finalAmount: (map['final_amount'] as num?)?.toDouble(),
      finalPaymentPaid: map['final_payment_paid'] as bool? ?? false,
      status: DeliveryGroupStatus.fromString(
          map['status'] as String? ?? 'placed'),
      riderId: map['rider_id'] as String?,
      deliveryPin: map['delivery_pin'] as String?,
      deliveryStage: map['delivery_stage'] as String?,
      scheduledFor: map['scheduled_for'] != null
          ? DateTime.parse(map['scheduled_for'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String studentId;
  final String deliveryType;
  final String? deliveryLocation;
  final String? studentNote;
  final double commitmentFeeTotal;
  final double? finalAmount;
  final bool finalPaymentPaid;
  final DeliveryGroupStatus status;
  final String? riderId;
  final String? deliveryPin;
  final String? deliveryStage;
  final DateTime? scheduledFor;
  final DateTime createdAt;

  String get shortId => '#${id.substring(0, 8).toUpperCase()}';

  bool get isTerminal =>
      status == DeliveryGroupStatus.completed ||
      status == DeliveryGroupStatus.cancelled;
}

enum DeliveryGroupStatus {
  placed,
  commitmentPaid,
  awaitingFinalPayment,
  outForDelivery,
  completed,
  cancelled;

  static DeliveryGroupStatus fromString(String s) => switch (s) {
        'placed' => placed,
        'commitment_paid' => commitmentPaid,
        'awaiting_final_payment' => awaitingFinalPayment,
        'out_for_delivery' => outForDelivery,
        'completed' => completed,
        'cancelled' => cancelled,
        _ => placed,
      };

  String get rawValue => switch (this) {
        placed => 'placed',
        commitmentPaid => 'commitment_paid',
        awaitingFinalPayment => 'awaiting_final_payment',
        outForDelivery => 'out_for_delivery',
        completed => 'completed',
        cancelled => 'cancelled',
      };

  String get label => switch (this) {
        placed => 'Placed',
        commitmentPaid => 'Being Prepared',
        awaitingFinalPayment => 'Awaiting Payment',
        outForDelivery => 'Out for Delivery',
        completed => 'Completed',
        cancelled => 'Cancelled',
      };
}
