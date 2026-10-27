import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/order.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../delivery/delivery_record.dart';
import '../pool/pool_order.dart';

/// Pickup location + customer contact for a currently active delivery.
class ActiveDeliveryDetail {
  const ActiveDeliveryDetail({
    required this.order,
    required this.pickupName,
    this.pickupAddress,
    this.customerName,
    this.customerPhone,
  });

  final Order order;
  final String pickupName;
  final String? pickupAddress;
  final String? customerName;
  final String? customerPhone;
}

/// Service wrapping all Supabase calls made by rider-only screens.
///
/// Security model: every mutation goes through a SECURITY DEFINER RPC
/// that checks `is_rider()` server-side (see Phase 5 block in
/// supabase/schema.sql). No client-side role check is needed here.
class RiderService {
  const RiderService(this._client, this._notifications);

  final SupabaseClient _client;

  /// Used to keep the customer posted as the delivery progresses, and to
  /// send them a one-off message from the active-delivery screen.
  final NotificationInboxService _notifications;

  // ── Online/offline ──────────────────────────────────────────────────

  Future<void> toggleOnline(bool online) async {
    await _client.rpc('toggle_rider_online', params: {'p_online': online});
  }

  // ── Stats ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getRiderStats() async {
    final result = await _client.rpc('get_rider_stats');
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Job Pool stream ────────────────────────────────────────────────

  /// Live stream of pool-eligible unassigned orders. Re-emits on every
  /// change to the `orders` table (via Supabase Realtime). Each emission
  /// includes pre-fetched vendor / around-request info so the pool card
  /// can render without additional round trips.
  Stream<List<PoolOrder>> streamJobPool() async* {
    // Helper: fetch pool-eligible orders via a one-shot REST query, then
    // enrich with vendor / around-request info.
    Future<List<PoolOrder>> fetchPool() async {
      final rows = await _client
          .from('orders')
          .select()
          .order('created_at', ascending: false);

      // Client-side filter: unassigned pool-eligible orders only.
      final pool = rows.where((m) {
        final riderId = m['rider_id'];
        if (riderId != null) return false;
        final status = m['status'] as String;
        final source = m['source'] as String;
        final type = m['type'] as String;
        final deliveryType = m['delivery_type'] as String?;
        const deliveryTypes = ['delivery', 'campus_delivery', 'hostel_delivery'];
        final transferredToRiderAt = m['transferred_to_rider_at'];
        return (source == 'uniflex' && status == 'ready' && transferredToRiderAt != null
                && deliveryTypes.contains(deliveryType))
            // partner/around orders enter the pool only after the commitment
            // fee is paid (status transitions from 'placed' to 'being_sourced').
            || (source == 'partner' && status == 'being_sourced' && deliveryTypes.contains(deliveryType))
            || (type == 'around' && status == 'being_sourced');
      }).toList();

      if (pool.isEmpty) return [];

      // Batch-fetch vendor info for food orders.
      final vendorIds = pool
          .where((m) => m['vendor_id'] != null && m['type'] == 'food')
          .map((m) => m['vendor_id'] as String)
          .toSet()
          .toList();

      final vendorsById = <String, Map<String, dynamic>>{};
      if (vendorIds.isNotEmpty) {
        final vendors = await _client
            .from('vendors')
            .select('id, name, location')
            .inFilter('id', vendorIds);
        for (final v in vendors) {
          vendorsById[v['id'] as String] = v;
        }
      }

      // Batch-fetch around_request pickup locations for 'around' orders.
      final aroundOrderIds = pool
          .where((m) => m['type'] == 'around')
          .map((m) => m['id'] as String)
          .toList();

      final aroundById = <String, Map<String, dynamic>>{};
      if (aroundOrderIds.isNotEmpty) {
        final arounds = await _client
            .from('around_requests')
            .select('order_id, pickup_location, item_description')
            .inFilter('order_id', aroundOrderIds);
        for (final a in arounds) {
          aroundById[a['order_id'] as String] = a;
        }
      }

      return pool.map((m) {
        final order = Order.fromMap(m);
        String pickupName;
        String? pickupAddress;
        String orderTypeLabel;

        if (order.isAround) {
          final around = aroundById[order.id];
          pickupName = 'Customer Pickup Point';
          pickupAddress = around?['pickup_location'] as String?;
          orderTypeLabel = 'Around';
        } else if (order.source == 'partner') {
          final vendor = vendorsById[order.vendorId ?? ''];
          pickupName = vendor?['name'] as String? ?? 'Partner Vendor';
          pickupAddress = vendor?['location'] as String?;
          orderTypeLabel = 'Partner Food';
        } else {
          pickupName = 'Uniflex Kitchen';
          pickupAddress = null;
          orderTypeLabel = 'Uniflex Food';
        }

        return PoolOrder(
          order: order,
          pickupName: pickupName,
          pickupAddress: pickupAddress,
          orderTypeLabel: orderTypeLabel,
        );
      }).toList();
    }

    // Emit initial data immediately so the pool is never blank.
    yield await fetchPool();

    // Then subscribe to Realtime for live updates.
    try {
      final orderStream = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false);

      await for (final _ in orderStream) {
        try {
          yield await fetchPool();
        } catch (e) {
          debugPrint('[RiderPool] Realtime fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[RiderPool] Realtime stream error: $e');
    }
  }

  // ── Active delivery stream ─────────────────────────────────────────

  /// Streams the rider's active deliveries.
  /// Includes both 'out_for_delivery' (normal delivery) and 'being_sourced'
  /// (partner/around orders the rider has accepted and is still sourcing).
  Stream<List<Order>> streamActiveDeliveries(String riderId) async* {
    Future<List<Order>> fetchActive() async {
      final rows = await _client
          .from('orders')
          .select()
          .eq('rider_id', riderId)
          .inFilter('status', ['out_for_delivery', 'being_sourced'])
          .order('created_at', ascending: false);
      return rows.map((m) => Order.fromMap(m)).toList();
    }

    yield await fetchActive();

    try {
      final stream = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('rider_id', riderId);

      await for (final _ in stream) {
        yield await fetchActive();
      }
    } catch (e) {
      debugPrint('[RiderDelivery] Realtime stream error: $e');
    }
  }

  // ── Pickup + customer detail (fetched once per active delivery) ──────

  /// Fetches the pickup location and customer contact for [order].
  /// Safe to call multiple times — each call is a fresh fetch.
  Future<ActiveDeliveryDetail> fetchActiveDeliveryDetail(Order order) async {
    String pickupName = 'Uniflex Kitchen';
    String? pickupAddress;

    if (order.isAround) {
      final data = await _client
          .from('around_requests')
          .select('pickup_location')
          .eq('order_id', order.id)
          .single();
      pickupName = 'Customer Pickup Point';
      pickupAddress = data['pickup_location'] as String?;
    } else if (order.source == 'partner' && order.vendorId != null) {
      final data = await _client
          .from('vendors')
          .select('name, location')
          .eq('id', order.vendorId!)
          .single();
      pickupName = data['name'] as String? ?? 'Partner Vendor';
      pickupAddress = data['location'] as String?;
    }

    // Fetch customer name + phone via SECURITY DEFINER RPC (privacy guard).
    String? customerName;
    String? customerPhone;
    try {
      final result = await _client
          .rpc('get_customer_info', params: {'p_order_id': order.id});
      final info = Map<String, dynamic>.from(result as Map);
      customerName = info['full_name'] as String?;
      customerPhone = info['phone'] as String?;
    } catch (_) {
      // Non-fatal: customer info is nice-to-have; show delivery anyway.
    }

    return ActiveDeliveryDetail(
      order: order,
      pickupName: pickupName,
      pickupAddress: pickupAddress,
      customerName: customerName,
      customerPhone: customerPhone,
    );
  }

  // ── Delivery actions ───────────────────────────────────────────────

  Future<void> acceptOrder(String orderId) async {
    await _client.rpc('accept_order', params: {'p_order_id': orderId});
    // accept_order moves the order to out_for_delivery, so this is the
    // "your rider is on the way" push. Non-throwing — see notifyOrderStatus.
    await _notifications.notifyOrderStatus(orderId);
  }

  Future<void> confirmPickup(String orderId) async {
    await _client.rpc('confirm_pickup', params: {'p_order_id': orderId});
  }

  Future<void> verifyDelivery(String orderId, String pin) async {
    await _client.rpc('verify_delivery', params: {
      'p_order_id': orderId,
      'p_pin': pin.trim().toUpperCase(),
    });
    await _notifications.notifyOrderStatus(orderId);
  }

  /// Sends the customer a free-text message about an order this rider is
  /// currently assigned to. Throws [NotifyException] on failure, because
  /// unlike the automatic pushes this is an explicit action.
  Future<void> messageCustomer({
    required String orderId,
    required String message,
  }) {
    return _notifications.messageCustomer(orderId: orderId, message: message);
  }

  // ── Sourcing flow (partner / around orders) ────────────────────────

  /// Flags an item as unavailable while sourcing. The DB records the flag
  /// and sends the student a notification. [orderItemId] is null for around
  /// requests (which have no line items).
  Future<void> flagItemUnavailable({
    required String orderId,
    String? orderItemId,
    required String productName,
    required int quantity,
  }) async {
    await _client.rpc('flag_item_unavailable', params: {
      'p_order_id': orderId,
      'p_order_item_id': orderItemId,
      'p_product_name': productName,
      'p_quantity': quantity,
    });
  }

  /// Confirms the items that are available and sets the final total.
  /// Moves the order to 'awaiting_final_payment' and notifies the student.
  Future<void> confirmSourcingItems({
    required String orderId,
    required double finalAmount,
  }) async {
    await _client.rpc('confirm_sourced_items', params: {
      'p_order_id': orderId,
      'p_final_amount': finalAmount,
    });
    await _notifications.notifyOrderStatus(orderId);
  }

  // ── Delivery history ───────────────────────────────────────────────

  Future<List<DeliveryRecord>> fetchDeliveryHistory() async {
    final records = await _client
        .from('delivery_records')
        .select()
        .order('completed_at', ascending: false)
        .limit(50);

    if (records.isEmpty) return [];

    final orderIds = records.map((m) => m['order_id'] as String).toList();

    final orders = await _client
        .from('orders')
        .select('id, type, total_amount, delivery_location, vendor_id, vendors(name)')
        .inFilter('id', orderIds);

    final ordersById = <String, Map<String, dynamic>>{
      for (final o in orders) o['id'] as String: o,
    };

    return records
        .map((m) => DeliveryRecord.fromMap(m, ordersById[m['order_id'] as String]))
        .toList();
  }
}
