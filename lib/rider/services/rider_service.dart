import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../delivery/delivery_record.dart';
import '../pool/pool_group.dart';
import '../pool/pool_order.dart';

/// Full customer info returned after a rider accepts a delivery group.
class GroupCustomerInfo {
  const GroupCustomerInfo({
    required this.fullName,
    this.nickname,
    required this.phone,
    this.email,
    this.deliveryLocation,
    this.locationDetails,
    this.studentNote,
    this.deliveryPin,
  });

  factory GroupCustomerInfo.fromMap(Map<String, dynamic> m) {
    return GroupCustomerInfo(
      fullName: m['full_name'] as String? ?? 'Customer',
      nickname: m['nickname'] as String?,
      phone: m['phone'] as String? ?? '',
      email: m['email'] as String?,
      deliveryLocation: m['delivery_location'] as String?,
      locationDetails: m['location_details'] as String?,
      studentNote: m['student_note'] as String?,
      deliveryPin: m['delivery_pin'] as String?,
    );
  }

  final String fullName;
  final String? nickname;
  final String phone;
  final String? email;
  final String? deliveryLocation;
  final String? locationDetails;
  final String? studentNote;
  final String? deliveryPin;

  String get displayName =>
      nickname != null ? '$fullName (@$nickname)' : fullName;
}

/// One vendor's item breakdown within a delivery group.
class GroupVendorItems {
  const GroupVendorItems({
    required this.vendorId,
    required this.vendorName,
    this.vendorLocation,
    required this.items,
    required this.packs,
    required this.subtotal,
  });

  final String vendorId;
  final String vendorName;
  final String? vendorLocation;
  final List<GroupLineItem> items;
  final List<GroupPack> packs;
  final double subtotal;

  List<GroupLineItem> get foodItems =>
      items.where((i) => i.section == 'food').toList();
  List<GroupLineItem> get drinkItems =>
      items.where((i) => i.section == 'drinks').toList();
  List<GroupLineItem> get otherItems =>
      items
          .where((i) => i.section != 'food' && i.section != 'drinks')
          .toList();
}

class GroupLineItem {
  const GroupLineItem({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.section,
    this.foodSubsection,
  });

  factory GroupLineItem.fromMap(Map<String, dynamic> m) {
    return GroupLineItem(
      productName: m['product_name'] as String,
      quantity: m['quantity'] as int,
      unitPrice: (m['unit_price'] as num).toDouble(),
      section: m['section'] as String? ?? 'others',
      foodSubsection: m['food_subsection'] as String?,
    );
  }

  final String productName;
  final int quantity;
  final double unitPrice;
  final String section;
  final String? foodSubsection;

  double get lineTotal => unitPrice * quantity;
}

class GroupPack {
  const GroupPack({
    required this.packIndex,
    required this.items,
  });

  final int packIndex;
  final List<GroupPackItem> items;

  String get label => 'Pack ${packIndex + 1}';
}

class GroupPackItem {
  const GroupPackItem({
    required this.productName,
    required this.quantity,
  });

  final String productName;
  final int quantity;
}

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
  /// includes pre-fetched vendor / errand-request info so the pool card
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
        // 'delivery' covers all named-location orders (Round 8+).
        // Keep campus_delivery/hostel_delivery for backward compat with any
        // pre-migration partner orders still in the DB.
        const deliveryTypes = ['delivery', 'campus_delivery', 'hostel_delivery'];
        final transferredToRiderAt = m['transferred_to_rider_at'];
        // Legacy around orders used being_sourced after commitment fee.
        final commitmentFeePaid = m['commitment_fee_paid'] as bool? ?? false;
        return (source == 'uniflex' && status == 'ready' && transferredToRiderAt != null
                && deliveryTypes.contains(deliveryType))
            // Partner food: pool-eligible once commitment fee paid (being_sourced).
            || (source == 'partner' && status == 'being_sourced' && deliveryTypes.contains(deliveryType))
            // Errand orders (Round 8+): fee paid upfront, status stays 'placed'.
            || (type == 'errand' && status == 'placed' && commitmentFeePaid)
            // Legacy around orders used being_sourced — keep for backward compat.
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

      // Batch-fetch errand_request pickup locations for errand orders.
      final errandOrderIds = pool
          .where((m) => m['type'] == 'around' || m['type'] == 'errand')
          .map((m) => m['id'] as String)
          .toList();

      final errandById = <String, Map<String, dynamic>>{};
      if (errandOrderIds.isNotEmpty) {
        final errands = await _client
            .from('errand_requests')
            .select('order_id, pickup_location, item_description')
            .inFilter('order_id', errandOrderIds);
        for (final a in errands) {
          errandById[a['order_id'] as String] = a;
        }
      }

      return pool.map((m) {
        final order = Order.fromMap(m);
        String pickupName;
        String? pickupAddress;
        String orderTypeLabel;

        if (order.isErrand) {
          final errand = errandById[order.id];
          pickupName = 'Customer Pickup Point';
          pickupAddress = errand?['pickup_location'] as String?;
          orderTypeLabel = 'Errand';
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

  // ── Unified pool stream (delivery groups + errands) ───────────────

  /// Live stream of the job pool: delivery groups + errand orders.
  Stream<({List<PoolGroup> groups, List<PoolOrder> errands})> streamPool() async* {
    Future<({List<PoolGroup> groups, List<PoolOrder> errands})>
        fetchPool() async {
      // Delivery groups in pool.
      final groupRows = await _client
          .from('delivery_groups')
          .select()
          .eq('status', 'commitment_paid')
          .isFilter('rider_id', null)
          .order('created_at', ascending: false);

      // Errand orders in pool.
      final errandRows = await _client
          .from('orders')
          .select()
          .eq('type', 'errand')
          .eq('status', 'placed')
          .eq('commitment_fee_paid', true)
          .isFilter('rider_id', null)
          .order('created_at', ascending: false);

      if (groupRows.isEmpty && errandRows.isEmpty) {
        return (groups: <PoolGroup>[], errands: <PoolOrder>[]);
      }

      // Enrich groups with vendor names.
      final groupIds = groupRows.map((m) => m['id'] as String).toList();
      final legs = groupIds.isNotEmpty
          ? await _client
              .from('orders')
              .select('delivery_group_id, vendor_id')
              .inFilter('delivery_group_id', groupIds)
          : <Map<String, dynamic>>[];

      final allVendorIds = {
        ...legs.map((l) => l['vendor_id'] as String?).whereType<String>(),
      }.toList();

      final vendorNames = <String, String>{};
      final vendorLocations = <String, String>{};
      if (allVendorIds.isNotEmpty) {
        final vendors = await _client
            .from('vendors')
            .select('id, name, location')
            .inFilter('id', allVendorIds);
        for (final v in vendors) {
          vendorNames[v['id'] as String] = v['name'] as String;
          if (v['location'] != null) {
            vendorLocations[v['id'] as String] = v['location'] as String;
          }
        }
      }

      final poolGroups = groupRows.map((m) {
        final group = DeliveryGroup.fromMap(m);
        final groupLegs =
            legs.where((l) => l['delivery_group_id'] == group.id).toList();
        final names = groupLegs
            .map((l) => vendorNames[l['vendor_id']] ?? 'Vendor')
            .toSet()
            .toList();
        return PoolGroup(
            group: group, vendorNames: names, legCount: groupLegs.length);
      }).toList();

      // Enrich errands with pickup info.
      final errandIds = errandRows.map((m) => m['id'] as String).toList();
      final errandDetails = errandIds.isNotEmpty
          ? await _client
              .from('errand_requests')
              .select('order_id, pickup_location, item_description, category')
              .inFilter('order_id', errandIds)
          : <Map<String, dynamic>>[];

      final errandById = <String, Map<String, dynamic>>{
        for (final e in errandDetails) e['order_id'] as String: e,
      };

      final poolErrands = errandRows.map((m) {
        final order = Order.fromMap(m);
        final details = errandById[order.id];
        return PoolOrder(
          order: order,
          pickupName: details?['pickup_location'] as String? ?? 'Errand pickup',
          pickupAddress: null,
          orderTypeLabel: 'Errand',
        );
      }).toList();

      return (groups: poolGroups, errands: poolErrands);
    }

    yield await fetchPool();

    try {
      final groupStream = _client
          .from('delivery_groups')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false);

      await for (final _ in groupStream) {
        try {
          yield await fetchPool();
        } catch (e) {
          debugPrint('[RiderPool] fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[RiderPool] stream error: $e');
    }
  }

  /// Streams a single delivery group by ID for live status updates.
  Stream<DeliveryGroup?> streamGroupDetail(String groupId) async* {
    Future<DeliveryGroup?> fetch() async {
      final rows = await _client
          .from('delivery_groups')
          .select()
          .eq('id', groupId)
          .limit(1);
      if (rows.isEmpty) return null;
      return DeliveryGroup.fromMap(rows.first);
    }

    yield await fetch();

    try {
      final stream = _client
          .from('delivery_groups')
          .stream(primaryKey: ['id']).eq('id', groupId);

      await for (final _ in stream) {
        try {
          yield await fetch();
        } catch (e) {
          debugPrint('[RiderGroupDetail] Realtime fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[RiderGroupDetail] Realtime stream error: $e');
    }
  }

  // ── Delivery group actions (Round 7) ──────────────────────────────

  /// Accepts a delivery group from the pool.
  Future<void> acceptDeliveryGroup(String groupId) async {
    await _client.rpc(
        'accept_delivery_group', params: {'p_group_id': groupId});
  }

  /// Verifies delivery of the entire group using the single delivery PIN.
  Future<void> verifyGroupDelivery(String groupId, String pin) async {
    await _client.rpc('verify_group_delivery', params: {
      'p_group_id': groupId,
      'p_pin': pin.trim().toUpperCase(),
    });
  }

  /// Fetches all order legs for a delivery group.
  Future<List<Order>> fetchGroupLegs(String groupId) async {
    final rows = await _client
        .from('orders')
        .select()
        .eq('delivery_group_id', groupId)
        .order('created_at');
    // Attach vendor names.
    final vendorIds = rows
        .map((m) => m['vendor_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final namesById = <String, String>{};
    if (vendorIds.isNotEmpty) {
      final vendors = await _client
          .from('vendors')
          .select('id, name')
          .inFilter('id', vendorIds);
      for (final v in vendors) {
        namesById[v['id'] as String] = v['name'] as String;
      }
    }
    return rows.map((m) {
      final withVendor = {
        ...m,
        if (m['vendor_id'] != null && namesById[m['vendor_id']] != null)
          'vendors': {'name': namesById[m['vendor_id']]},
      };
      return Order.fromMap(withVendor);
    }).toList();
  }

  // ── Active work stream ─────────────────────────────────────────────

  /// Streams the rider's active items: active delivery groups + active errand orders.
  Stream<({List<DeliveryGroup> groups, List<Order> errands})> streamActiveWork(
      String riderId) async* {
    Future<({List<DeliveryGroup> groups, List<Order> errands})>
        fetchActive() async {
      final groupRows = await _client
          .from('delivery_groups')
          .select()
          .eq('rider_id', riderId)
          .inFilter('status', [
            'rider_accepted',
            'awaiting_final_payment',
            'out_for_delivery',
          ])
          .order('created_at', ascending: false);

      final errandRows = await _client
          .from('orders')
          .select()
          .eq('rider_id', riderId)
          .eq('type', 'errand')
          .inFilter('status', ['being_sourced', 'out_for_delivery'])
          .order('created_at', ascending: false);

      return (
        groups: groupRows.map((m) => DeliveryGroup.fromMap(m)).toList(),
        errands: errandRows.map((m) => Order.fromMap(m)).toList(),
      );
    }

    yield await fetchActive();

    try {
      // Listen to both tables
      final groupStream = _client
          .from('delivery_groups')
          .stream(primaryKey: ['id'])
          .eq('rider_id', riderId);

      await for (final _ in groupStream) {
        try {
          yield await fetchActive();
        } catch (e) {
          debugPrint('[RiderActive] fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[RiderActive] stream error: $e');
    }
  }

  // ── Pickup + customer detail (fetched once per active delivery) ──────

  /// Fetches the pickup location and customer contact for [order].
  /// Safe to call multiple times — each call is a fresh fetch.
  Future<ActiveDeliveryDetail> fetchActiveDeliveryDetail(Order order) async {
    String pickupName = 'Uniflex Kitchen';
    String? pickupAddress;

    if (order.isErrand) {
      final data = await _client
          .from('errand_requests')
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

  Future<void> verifyDelivery(String orderId, String pin) async {
    await _client.rpc('verify_delivery', params: {
      'p_order_id': orderId,
      'p_pin': pin.trim().toUpperCase(),
    });
    await _notifications.notifyOrderStatus(orderId);
  }

  // ── Delivery group actions (new flow) ─────────────────────────────

  /// Sets the final food total for a delivery group.
  /// Rider can call this until the student pays.
  Future<void> setGroupFinalPrice(String groupId, double finalAmount) async {
    await _client.rpc('set_delivery_group_final_price', params: {
      'p_group_id': groupId,
      'p_final_amount': finalAmount,
    });
  }

  /// Fetches full customer info for an accepted delivery group.
  Future<GroupCustomerInfo> getGroupCustomerInfo(String groupId) async {
    final result = await _client.rpc(
      'get_group_customer_info',
      params: {'p_group_id': groupId},
    );
    return GroupCustomerInfo.fromMap(Map<String, dynamic>.from(result as Map));
  }

  /// Fetches full item breakdown for a delivery group (vendor list with packs/drinks/others).
  Future<List<GroupVendorItems>> getGroupItems(String groupId) async {
    final result = await _client.rpc(
      'get_group_items',
      params: {'p_group_id': groupId},
    );
    final raw = result as List<dynamic>;
    return raw.map((v) {
      final vm = Map<String, dynamic>.from(v as Map);
      final itemsRaw = vm['items'] as List<dynamic>? ?? [];
      final packsRaw = vm['packs'] as List<dynamic>? ?? [];

      final items = itemsRaw
          .map((i) => GroupLineItem.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList();

      final packs = packsRaw.map((p) {
        final pm = Map<String, dynamic>.from(p as Map);
        final packItems = (pm['items'] as List<dynamic>? ?? [])
            .map((pi) {
              final pim = Map<String, dynamic>.from(pi as Map);
              return GroupPackItem(
                productName: pim['product_name'] as String,
                quantity: pim['quantity'] as int,
              );
            })
            .toList();
        return GroupPack(
          packIndex: pm['pack_index'] as int,
          items: packItems,
        );
      }).toList();

      return GroupVendorItems(
        vendorId: vm['vendor_id'] as String,
        vendorName: vm['vendor_name'] as String,
        vendorLocation: vm['vendor_location'] as String?,
        items: items,
        packs: packs,
        subtotal: (vm['subtotal'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  // ── Delivery history ───────────────────────────────────────────────

  Future<List<DeliveryRecord>> fetchDeliveryHistory() async {
    // Completed deliveries from delivery_records (traditional).
    final records = await _client
        .from('delivery_records')
        .select()
        .order('completed_at', ascending: false)
        .limit(100);

    // Also get completed/cancelled groups for this rider.
    final riderId = _client.auth.currentUser?.id;
    if (riderId == null) return [];

    final groupRows = await _client
        .from('delivery_groups')
        .select()
        .eq('rider_id', riderId)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false)
        .limit(100);

    // Build group-based history entries.
    final groupHistory = groupRows.map((m) {
      final group = DeliveryGroup.fromMap(m);
      return DeliveryRecord(
        id: group.id,
        orderId: group.id,
        completedAt: group.createdAt,
        vendorName: '${group.deliveryLocation ?? 'Delivery'} (group)',
        orderTotal: group.finalAmount ?? group.commitmentFeeTotal,
        deliveryLocation: group.deliveryLocation,
        orderType: 'food',
        wasCancelled: group.status == DeliveryGroupStatus.cancelled,
      );
    }).toList();

    // Build from delivery_records.
    if (records.isEmpty) return groupHistory;

    final orderIds = records.map((m) => m['order_id'] as String).toList();
    final orders = await _client
        .from('orders')
        .select(
            'id, type, total_amount, delivery_location, vendor_id, vendors(name)')
        .inFilter('id', orderIds);

    final ordersById = <String, Map<String, dynamic>>{
      for (final o in orders) o['id'] as String: o,
    };

    final recordHistory = records
        .map((m) =>
            DeliveryRecord.fromMap(m, ordersById[m['order_id'] as String]))
        .toList();

    // Merge and sort by completedAt desc.
    final merged = [...recordHistory, ...groupHistory];
    merged.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return merged;
  }
}
