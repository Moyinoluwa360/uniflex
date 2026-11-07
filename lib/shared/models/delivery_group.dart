import '../utils/local_time.dart';

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
    this.locationDetails,
    this.deliveryLocationId,
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
    this.cancelledByStudent = false,
    this.completedAt,
    this.cancelledAt,
    this.isGift = false,
    this.giftRecipientId,
    this.giftRecipientNickname,
    this.giftMessage,
  });

  factory DeliveryGroup.fromMap(Map<String, dynamic> map) {
    return DeliveryGroup(
      id: map['id'] as String,
      studentId: map['student_id'] as String,
      deliveryType: map['delivery_type'] as String,
      deliveryLocation: map['delivery_location'] as String?,
      locationDetails: map['location_details'] as String?,
      deliveryLocationId: map['delivery_location_id'] as String?,
      studentNote: map['student_note'] as String?,
      commitmentFeeTotal:
          (map['commitment_fee_total'] as num?)?.toDouble() ?? 0,
      finalAmount: (map['final_amount'] as num?)?.toDouble(),
      finalPaymentPaid: map['final_payment_paid'] as bool? ?? false,
      status:
          DeliveryGroupStatus.fromString(map['status'] as String? ?? 'placed'),
      riderId: map['rider_id'] as String?,
      deliveryPin: map['delivery_pin'] as String?,
      deliveryStage: map['delivery_stage'] as String?,
      scheduledFor: map['scheduled_for'] != null
          ? DateTime.parse(map['scheduled_for'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      cancelledByStudent: map['cancelled_by_student'] as bool? ?? false,
      completedAt: parseServerTime(map['completed_at']),
      cancelledAt: parseServerTime(map['cancelled_at']),
      isGift: map['is_gift'] as bool? ?? false,
      giftRecipientId: map['gift_recipient_id'] as String?,
      giftRecipientNickname: map['gift_recipient_nickname'] as String?,
      giftMessage: map['gift_message'] as String?,
    );
  }

  final String id;
  final String studentId;
  final String deliveryType;
  final String? deliveryLocation;
  final String? locationDetails;
  final String? deliveryLocationId;
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
  final bool cancelledByStudent;

  /// Server time (now()) stamped ONCE when the rider's PIN was verified /
  /// the order was cancelled, in the phone's local time. Every screen shows
  /// this and nothing else as "the time it was completed".
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  /// Gift orders: the sender is [studentId]; the recipient only ever appears
  /// here as a nickname.
  final bool isGift;
  final String? giftRecipientId;
  final String? giftRecipientNickname;
  final String? giftMessage;

  String get shortId => '#${id.substring(0, 8).toUpperCase()}';

  bool get isTerminal =>
      status == DeliveryGroupStatus.completed ||
      status == DeliveryGroupStatus.cancelled;
}

enum DeliveryGroupStatus {
  placed,
  commitmentPaid,
  riderAccepted,
  awaitingFinalPayment,
  outForDelivery,
  completed,
  cancelled;

  static DeliveryGroupStatus fromString(String s) => switch (s) {
        'placed' => placed,
        'commitment_paid' => commitmentPaid,
        'rider_accepted' => riderAccepted,
        'awaiting_final_payment' => awaitingFinalPayment,
        'out_for_delivery' => outForDelivery,
        'completed' => completed,
        'cancelled' => cancelled,
        _ => placed,
      };

  String get rawValue => switch (this) {
        placed => 'placed',
        commitmentPaid => 'commitment_paid',
        riderAccepted => 'rider_accepted',
        awaitingFinalPayment => 'awaiting_final_payment',
        outForDelivery => 'out_for_delivery',
        completed => 'completed',
        cancelled => 'cancelled',
      };

  String get label => switch (this) {
        placed => 'Placed',
        commitmentPaid => 'In Rider Pool',
        riderAccepted => 'Rider Accepted',
        awaitingFinalPayment => 'Awaiting Payment',
        outForDelivery => 'Out for Delivery',
        completed => 'Completed',
        cancelled => 'Cancelled',
      };
}
