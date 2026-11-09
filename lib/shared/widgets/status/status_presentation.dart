import '../../models/delivery_group.dart';
import '../../models/order.dart';
import 'app_status_label.dart';

/// How a status is shown: the words and the tone (dot colour).
class StatusPresentation {
  const StatusPresentation(this.label, this.tone);

  final String label;
  final StatusTone tone;

  @override
  bool operator ==(Object other) =>
      other is StatusPresentation && other.label == label && other.tone == tone;

  @override
  int get hashCode => Object.hash(label, tone);

  @override
  String toString() => 'StatusPresentation($label, $tone)';
}

/// The ONE place that turns a status into words + tone. Every existing label
/// is kept except the delivery-group `In Rider Pool`, which now reads
/// `Finding a rider` (display only; the enum and the database value are
/// untouched).
///
/// Tones: placed / in the pool / awaiting payment → waiting; rider accepted,
/// preparing, ready, out for delivery, being sourced → live; completed →
/// done; cancelled → cancelled.
abstract final class StatusPresenter {
  /// A food or errand [OrderStatus]. Pass [isErrand] for the errand wording
  /// the student Home uses ("Errand placed", "Rider assigned", "On the way").
  static StatusPresentation order(OrderStatus s, {bool isErrand = false}) {
    if (isErrand) {
      switch (s) {
        case OrderStatus.placed:
          return const StatusPresentation('Errand placed', StatusTone.waiting);
        case OrderStatus.beingSourced:
          return const StatusPresentation('Rider assigned', StatusTone.live);
        case OrderStatus.outForDelivery:
          return const StatusPresentation('On the way', StatusTone.live);
        default:
          break;
      }
    }
    return switch (s) {
      OrderStatus.placed => const StatusPresentation('Order Placed', StatusTone.waiting),
      OrderStatus.preparing => const StatusPresentation('Preparing', StatusTone.live),
      OrderStatus.ready => const StatusPresentation('Ready', StatusTone.live),
      OrderStatus.outForDelivery =>
        const StatusPresentation('Out for Delivery', StatusTone.live),
      OrderStatus.readyForPickup =>
        const StatusPresentation('Ready for Pickup', StatusTone.live),
      OrderStatus.completed => const StatusPresentation('Completed', StatusTone.done),
      OrderStatus.cancelled =>
        const StatusPresentation('Cancelled', StatusTone.cancelled),
      OrderStatus.beingSourced =>
        const StatusPresentation('Being Sourced', StatusTone.live),
      OrderStatus.awaitingFinalPayment =>
        const StatusPresentation('Awaiting Final Payment', StatusTone.waiting),
    };
  }

  /// A [DeliveryGroupStatus].
  static StatusPresentation group(DeliveryGroupStatus s) => switch (s) {
        DeliveryGroupStatus.placed =>
          const StatusPresentation('Placed', StatusTone.waiting),
        DeliveryGroupStatus.commitmentPaid =>
          const StatusPresentation('Finding a rider', StatusTone.waiting),
        DeliveryGroupStatus.riderAccepted =>
          const StatusPresentation('Rider Accepted', StatusTone.live),
        DeliveryGroupStatus.awaitingFinalPayment =>
          const StatusPresentation('Awaiting Payment', StatusTone.waiting),
        DeliveryGroupStatus.outForDelivery =>
          const StatusPresentation('Out for Delivery', StatusTone.live),
        DeliveryGroupStatus.completed =>
          const StatusPresentation('Completed', StatusTone.done),
        DeliveryGroupStatus.cancelled =>
          const StatusPresentation('Cancelled', StatusTone.cancelled),
      };

  /// A gift's status string (`gift_deliveries.status`).
  static StatusPresentation gift(String status) => switch (status) {
        'preparing' => const StatusPresentation('Being prepared', StatusTone.live),
        'on_the_way' => const StatusPresentation('On its way', StatusTone.live),
        'delivered' => const StatusPresentation('Delivered', StatusTone.done),
        'cancelled' => const StatusPresentation('Cancelled', StatusTone.cancelled),
        _ => const StatusPresentation('Order placed', StatusTone.waiting),
      };

  /// Any raw database status string (orders and delivery groups share most
  /// values). Unknown strings read as an order that was just placed, the same
  /// fallback the models use.
  static StatusPresentation raw(String status) {
    switch (status) {
      case 'commitment_paid':
      case 'rider_accepted':
        return group(DeliveryGroupStatus.fromString(status));
      case 'placed':
        return order(OrderStatus.placed);
      default:
        return order(OrderStatus.fromString(status));
    }
  }
}
