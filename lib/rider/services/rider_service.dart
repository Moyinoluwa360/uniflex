import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/order.dart';
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
  const RiderService(this._client);

  final SupabaseClient _client;

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
    final orderStream = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false);

    await for (final rows in orderStream) {
      // Client-side filter: unassigned pool-eligible orders only.
      final pool = rows.where((m) {
        final riderId = m['rider_id'];
        if (riderId != null) return false;
        final status = m['status'] as String;
        final source = m['source'] as String;
        final type = m['type'] as String;
        final deliveryType = m['delivery_type'] as String?;
        // Campus/Hostel deliveries are rider-fulfilled just like plain
        // 'delivery' — the student food-order path only ever sends the
        // campus_delivery/hostel_delivery variants (never bare 'delivery').
        const deliveryTypes = ['delivery', 'campus_delivery', 'hostel_delivery'];
        return (source == 'uniflex' && status == 'ready' && deliveryTypes.contains(deliveryType))
            || (source == 'partner' && status == 'placed' && deliveryTypes.contains(deliveryType))
            || (type == 'around' && status == 'placed');
      }).toList();

      if (pool.isEmpty) {
        yield [];
        continue;
      }

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

      yield pool.map((m) {
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
  }

  // ── Active delivery stream ─────────────────────────────────────────

  /// Streams the rider's current active delivery (status='out_for_delivery'),
  /// if one exists. Re-emits when the order status or delivery_stage changes.
  Stream<Order?> streamActiveDelivery(String riderId) async* {
    final stream = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('rider_id', riderId);

    await for (final rows in stream) {
      final active = rows
          .where((m) => m['status'] == 'out_for_delivery')
          .toList();
      yield active.isEmpty ? null : Order.fromMap(active.first);
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
  }

  Future<void> confirmPickup(String orderId) async {
    await _client.rpc('confirm_pickup', params: {'p_order_id': orderId});
  }

  Future<void> verifyDelivery(String orderId, String pin) async {
    await _client.rpc('verify_delivery', params: {
      'p_order_id': orderId,
      'p_pin': pin.trim().toUpperCase(),
    });
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
