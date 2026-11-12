import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/services/supabase/supabase_providers.dart';
import 'checkout_draft.dart';

/// Thrown when the server answers a payment with an application error
/// code (e.g. a wrong PIN). Its text is just the code, so the shared
/// [AppErrorMapper] turns it into the friendly message.
class PaymentException implements Exception {
  const PaymentException(this.code);
  final String code;

  @override
  String toString() => code;
}

/// What the server returns after a successful payment.
class PaidOrderResult {
  const PaidOrderResult({
    required this.kind,
    required this.orderId,
    this.groupId,
    this.totalCharged = 0,
    this.serviceCharge = 0,
    this.planOverBudget = false,
    this.replayed = false,
  });

  factory PaidOrderResult.fromMap(Map<String, dynamic> m) => PaidOrderResult(
        kind: m['kind'] as String? ?? '',
        orderId: m['order_id'] as String,
        groupId: m['group_id'] as String?,
        totalCharged: (m['total_charged'] as num?)?.toDouble() ?? 0,
        serviceCharge: (m['service_charge'] as num?)?.toDouble() ?? 0,
        planOverBudget: m['plan_over_budget'] as bool? ?? false,
        replayed: m['replayed'] as bool? ?? false,
      );

  /// 'delivery' | 'pickup' | 'errand'
  final String kind;

  /// Delivery: the group id (the ONE order the student, rider and Admin
  /// all see). Pickup / errand: the order id.
  final String orderId;
  final String? groupId;
  final double totalCharged;
  final double serviceCharge;
  final bool planOverBudget;

  /// True when the server recognised the idempotency key and returned the
  /// order that already existed instead of creating another.
  final bool replayed;
}

/// The only way the app creates an order. Every method is ONE server call
/// that verifies the PIN, computes every amount, debits the wallet and
/// creates the whole order in a single transaction. Nothing is created
/// unless it is paid.
abstract class OrderPaymentRepository {
  Future<PaidOrderResult> payDelivery({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  });

  Future<PaidOrderResult> payPickup({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  });

  Future<PaidOrderResult> payErrand({
    required String idempotencyKey,
    required String pin,
    required String categoryKey,
    required String pickupLocation,
    required String dropoffLocation,
    required String itemDescription,
    String? deliveryLocationId,
    String? locationDetails,
  });
}

class SupabaseOrderPaymentRepository implements OrderPaymentRepository {
  const SupabaseOrderPaymentRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<PaidOrderResult> payDelivery({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  }) async {
    final loc = draft.location;
    if (loc == null) throw const PaymentException('LOCATION_NOT_FOUND');
    // A gift is the same delivery order plus a recipient: the server
    // re-checks the recipient, then runs the normal order creation.
    final result = await _client.rpc(
        draft.isGift ? 'create_paid_gift_order' : 'create_paid_delivery_order',
        params: {
          'p_idempotency_key': idempotencyKey,
          'p_pin': pin,
          'p_legs': [for (final v in draft.vendors) _leg(v)],
          'p_delivery_location_id': loc.id,
          'p_location_details': draft.locationDetails,
          'p_student_note': draft.note,
          if (draft.isGift) ...{
            'p_recipient_email': draft.giftRecipient!.email,
            'p_gift_message': draft.giftMessage,
          },
        });
    return _parse(result);
  }

  @override
  Future<PaidOrderResult> payPickup({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  }) async {
    if (draft.vendors.length != 1) {
      throw const PaymentException('PICKUP_UNIFLEX_ONLY');
    }
    final v = draft.vendors.first;
    final result = await _client.rpc('create_paid_pickup_order', params: {
      'p_idempotency_key': idempotencyKey,
      'p_pin': pin,
      'p_vendor_id': v.vendorId,
      'p_items': _items(v),
      'p_packs': _packs(v),
      if (draft.scheduledFor != null)
        'p_scheduled_for': draft.scheduledFor!.toUtc().toIso8601String(),
      'p_notes': draft.note,
    });
    return _parse(result);
  }

  @override
  Future<PaidOrderResult> payErrand({
    required String idempotencyKey,
    required String pin,
    required String categoryKey,
    required String pickupLocation,
    required String dropoffLocation,
    required String itemDescription,
    String? deliveryLocationId,
    String? locationDetails,
  }) async {
    final result = await _client.rpc('create_paid_errand', params: {
      'p_idempotency_key': idempotencyKey,
      'p_pin': pin,
      'p_category': categoryKey,
      'p_pickup_location': pickupLocation,
      'p_dropoff_location': dropoffLocation,
      'p_item_description': itemDescription,
      'p_delivery_location_id': deliveryLocationId,
      'p_location_details': locationDetails,
    });
    return _parse(result);
  }

  // Choices only: product ids, quantities and pack allocation.
  static List<Map<String, dynamic>> _items(DraftVendor v) => [
        for (final i in v.items)
          {'product_id': i.productId, 'quantity': i.quantity},
      ];

  static List<Map<String, dynamic>> _packs(DraftVendor v) => [
        for (final p in v.packs)
          {
            'items': [
              for (final e in p.entries)
                {'product_id': e.key, 'quantity': e.value},
            ],
          },
      ];

  /// The exact leg map sent to `create_paid_delivery_order` (for tests).
  @visibleForTesting
  static Map<String, dynamic> legForTest(DraftVendor v) => _leg(v);

  static Map<String, dynamic> _leg(DraftVendor v) => {
        'vendor_id': v.vendorId,
        'ordering_style': v.orderingStyle,
        'items': _items(v),
        'packs': _packs(v),
      };

  static PaidOrderResult _parse(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    final error = map['error'] as String?;
    if (error != null) throw PaymentException(error);
    return PaidOrderResult.fromMap(map);
  }
}

final orderPaymentRepositoryProvider = Provider<OrderPaymentRepository>((ref) {
  return SupabaseOrderPaymentRepository(ref.watch(supabaseClientProvider));
});
