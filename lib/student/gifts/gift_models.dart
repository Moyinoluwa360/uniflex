import '../../shared/order_breakdown/order_breakdown_models.dart';
import '../../shared/utils/local_time.dart';

/// Who a gift is going to, as the sender sees it after pressing "Find":
/// a nickname and a masked email — nothing else about that person.
class GiftRecipient {
  const GiftRecipient({
    required this.email,
    required this.nickname,
    required this.maskedEmail,
  });

  /// What the sender typed (re-checked by the server when the order is
  /// created).
  final String email;
  final String nickname;

  /// e.g. `j***@gmail.com`
  final String maskedEmail;
}

/// Result of `lookup_gift_recipient`.
sealed class GiftLookupResult {
  const GiftLookupResult();

  factory GiftLookupResult.fromMap(String typedEmail, Map<String, dynamic> m) {
    if (m['ok'] == true) {
      return GiftLookupFound(GiftRecipient(
        email: typedEmail.trim(),
        nickname: m['nickname'] as String? ?? '',
        maskedEmail: m['masked_email'] as String? ?? '',
      ));
    }
    return GiftLookupFailed(m['reason'] as String? ?? 'NOT_FOUND');
  }
}

class GiftLookupFound extends GiftLookupResult {
  const GiftLookupFound(this.recipient);
  final GiftRecipient recipient;
}

class GiftLookupFailed extends GiftLookupResult {
  const GiftLookupFailed(this.reason);

  /// NOT_FOUND | SELF | RATE_LIMITED
  final String reason;

  /// The one sentence the sender sees.
  String get message => switch (reason) {
        'SELF' => "You can't send a gift to yourself.",
        'RATE_LIMITED' =>
          'Too many searches. Please wait a while and try again.',
        _ => 'No student found with that email.',
      };
}

/// Words for the status line (shared by the recipient's screens).
String giftStatusLabel(String status) => switch (status) {
      'preparing' => 'Being prepared',
      'on_the_way' => 'On its way',
      'delivered' => 'Delivered',
      'cancelled' => 'Cancelled',
      _ => 'Order placed',
    };

/// A gift as its RECIPIENT sees it — one row of `gift_deliveries`.
/// Deliberately has no money fields: the table has none.
class GiftDelivery {
  const GiftDelivery({
    required this.groupId,
    required this.senderNickname,
    required this.status,
    required this.items,
    required this.createdAt,
    this.message,
    this.deliveryPin,
    this.deliveryLocation,
    this.locationDetails,
  });

  factory GiftDelivery.fromMap(Map<String, dynamic> m) => GiftDelivery(
        groupId: m['group_id'] as String,
        senderNickname: m['sender_nickname'] as String? ?? 'Someone',
        message: m['message'] as String?,
        status: m['status'] as String? ?? 'placed',
        deliveryPin: m['delivery_pin'] as String?,
        deliveryLocation: m['delivery_location'] as String?,
        locationDetails: m['location_details'] as String?,
        items: m['items'] is Map
            ? OrderBreakdownData.fromJson(
                Map<String, dynamic>.from(m['items'] as Map))
            : const OrderBreakdownData(
                orderId: '', kind: 'delivery', vendors: []),
        createdAt: parseServerTime(m['created_at']) ?? DateTime.now(),
      );

  final String groupId;
  final String senderNickname;
  final String? message;

  /// placed | preparing | on_the_way | delivered | cancelled
  final String status;

  /// The PIN the recipient gives the rider; cleared by the server once the
  /// gift is delivered or cancelled.
  final String? deliveryPin;
  final String? deliveryLocation;
  final String? locationDetails;
  final OrderBreakdownData items;
  final DateTime createdAt;

  bool get isEnded => status == 'delivered' || status == 'cancelled';
  String get statusLabel => giftStatusLabel(status);
  String get shortId => '#${groupId.substring(0, 8).toUpperCase()}';
}
