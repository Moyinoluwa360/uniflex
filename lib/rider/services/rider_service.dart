import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../jobs/rider_job.dart';

/// One side of a gift delivery (the person who receives it, or who paid).
/// Never contains a matric number.
class GiftParty {
  const GiftParty({
    required this.fullName,
    this.nickname,
    this.phone = '',
    this.email,
    this.locationDetails,
  });

  factory GiftParty.fromMap(Map<String, dynamic> m) => GiftParty(
        fullName: m['full_name'] as String? ?? 'Student',
        nickname: m['nickname'] as String?,
        phone: m['phone'] as String? ?? '',
        email: m['email'] as String?,
        locationDetails: m['location_details'] as String?,
      );

  final String fullName;
  final String? nickname;
  final String phone;
  final String? email;
  final String? locationDetails;
}

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
    this.giftRecipient,
    this.giftSender,
  });

  factory GroupCustomerInfo.fromMap(Map<String, dynamic> m) {
    final gift = m['is_gift'] == true && m['gift'] is Map
        ? Map<String, dynamic>.from(m['gift'] as Map)
        : null;
    GiftParty? party(String k) => gift != null && gift[k] is Map
        ? GiftParty.fromMap(Map<String, dynamic>.from(gift[k] as Map))
        : null;
    return GroupCustomerInfo(
      giftRecipient: party('recipient'),
      giftSender: party('sender'),
      fullName: m['full_name'] as String? ?? 'Customer',
      nickname: m['nickname'] as String?,
      phone: m['phone'] as String? ?? '',
      email: m['email'] as String?,
      deliveryLocation: m['delivery_location'] as String?,
      locationDetails: m['location_details'] as String?,
      studentNote: m['student_note'] as String?,
    );
  }

  final String fullName;
  final String? nickname;
  final String phone;
  final String? email;
  final String? deliveryLocation;
  final String? locationDetails;
  final String? studentNote;

  /// Set only for gift deliveries: who the food goes to, and who paid.
  final GiftParty? giftRecipient;
  final GiftParty? giftSender;

  bool get isGift => giftRecipient != null;

  String get displayName =>
      nickname != null ? '$fullName (@$nickname)' : fullName;
}

/// The customer on an active errand (name + phone, only while it is live).
class ErrandCustomer {
  const ErrandCustomer({this.name, this.phone});

  final String? name;
  final String? phone;
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

  // ── Job lists (rider-safe RPCs: one entry per checkout, no fees) ─────

  /// Re-runs [fetch] now and whenever a rider job signal arrives (Realtime).
  /// `rider_job_signals` holds only ids — riders cannot read the order tables
  /// any more, so this is the "something changed, refetch" nudge. A failed
  /// FIRST load surfaces as a stream error (so the screen can show Retry); a
  /// failed refresh keeps the last data and is only logged.
  Stream<T> _live<T>(Future<T> Function() fetch, String tag) {
    late final StreamController<T> controller;
    StreamSubscription<dynamic>? sub;
    Timer? safety;
    var inFlight = false;
    var again = false;

    Future<void> load({bool initial = false}) async {
      if (inFlight) {
        again = true;
        return;
      }
      inFlight = true;
      try {
        final value = await fetch();
        if (!controller.isClosed) controller.add(value);
      } catch (e, st) {
        debugPrint('[$tag] fetch error: $e');
        if (initial && !controller.isClosed) controller.addError(e, st);
      } finally {
        inFlight = false;
        if (again) {
          again = false;
          unawaited(load());
        }
      }
    }

    controller = StreamController<T>(
      onListen: () {
        unawaited(load(initial: true));
        // Safety net in case a realtime nudge is missed.
        safety = Timer.periodic(
            const Duration(seconds: 45), (_) => unawaited(load()));
        var first = true; // the first emission is just the current snapshot
        sub = _client
            .from('rider_job_signals')
            .stream(primaryKey: ['id'])
            .order('id', ascending: false)
            .limit(1)
            .listen(
              (_) {
                if (first) {
                  first = false;
                  return;
                }
                unawaited(load());
              },
              onError: (Object e) => debugPrint('[$tag] realtime signals: $e'),
            );
      },
      onCancel: () async {
        safety?.cancel();
        await sub?.cancel();
      },
    );
    return controller.stream;
  }

  /// The Jobs tab: food deliveries + errands that can be accepted.
  Future<RiderPool> fetchJobPool() async {
    final raw = await _client.rpc('rider_job_pool');
    return RiderPool.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Stream<RiderPool> streamJobPool() => _live(fetchJobPool, 'RiderPool');

  /// This rider's active jobs (food + errands), one entry per checkout.
  Future<List<RiderJob>> fetchActiveJobs() async {
    final raw = await _client.rpc('rider_active_jobs');
    return ((raw as List?) ?? const [])
        .map((e) => RiderJob.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Stream<List<RiderJob>> streamActiveJobs() =>
      _live(fetchActiveJobs, 'RiderActive');

  /// Finished jobs (completed or cancelled), one entry per checkout, newest
  /// first, each carrying the server's single completed_at / cancelled_at.
  Future<List<RiderJob>> fetchHistory() async {
    final raw = await _client.rpc('rider_history');
    return ((raw as List?) ?? const [])
        .map((e) => RiderJob.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  /// Read-only details of one finished job.
  Future<RiderJobDetail> fetchHistoryItem(String id) async {
    final raw = await _client.rpc('rider_history_item', params: {'p_id': id});
    return RiderJobDetail.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  /// This rider's view of one of their food jobs (null if it is not theirs).
  Future<RiderGroupDetail?> fetchGroupDetail(String groupId) async {
    final raw =
        await _client.rpc('rider_group_detail', params: {'p_id': groupId});
    if (raw == null) return null;
    return RiderGroupDetail.fromJson(Map<String, dynamic>.from(raw as Map));
  }

  Stream<RiderGroupDetail?> streamGroupDetail(String groupId) =>
      _live(() => fetchGroupDetail(groupId), 'RiderGroupDetail');

  // ── Delivery group actions (Round 7) ──────────────────────────────

  /// Accepts a delivery group from the pool.
  Future<void> acceptDeliveryGroup(String groupId) async {
    await _client.rpc('accept_delivery_group', params: {'p_group_id': groupId});
  }

  /// Verifies delivery of the entire group using the single delivery PIN.
  Future<void> verifyGroupDelivery(String groupId, String pin) async {
    await _client.rpc('verify_group_delivery', params: {
      'p_group_id': groupId,
      'p_pin': pin.trim().toUpperCase(),
    });
  }

  // ── Errand customer (name + phone while the errand is live) ───────

  Future<ErrandCustomer> fetchErrandCustomer(String orderId) async {
    try {
      final result = await _client
          .rpc('get_customer_info', params: {'p_order_id': orderId});
      final info = Map<String, dynamic>.from(result as Map);
      return ErrandCustomer(
        name: info['full_name'] as String?,
        phone: info['phone'] as String?,
      );
    } catch (e) {
      debugPrint('[RiderService] errand customer info failed: $e');
      return const ErrandCustomer();
    }
  }

  // ── Delivery actions ───────────────────────────────────────────────

  Future<void> acceptOrder(String orderId) async {
    await _client.rpc('accept_order', params: {'p_order_id': orderId});
    // The "A rider has accepted your order" notification is written and
    // pushed by a database trigger (Pack 4A).
  }

  Future<void> verifyDelivery(String orderId, String pin) async {
    await _client.rpc('verify_delivery', params: {
      'p_order_id': orderId,
      'p_pin': pin.trim().toUpperCase(),
    });
    // "Your order has been delivered" comes from a database trigger.
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
}
