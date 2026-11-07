import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/delivery_location.dart';
import '../../shared/models/order.dart';
import '../../shared/models/order_item.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../gifts/gift_models.dart';

// ---------------------------------------------------------------------------
// Read providers
// ---------------------------------------------------------------------------

/// All orders for the signed-in student, newest first, live via Supabase
/// Realtime. Post-testing fixes, Section 12: this used to be a one-shot
/// FutureProvider, which is the root cause behind "Kitchen marks Ready
/// but the Student's Orders tab doesn't reliably reflect it" — nothing
/// ever re-fetched until the student manually pulled to refresh. Now any
/// status change to one of the student's orders re-emits automatically.
final studentOrdersProvider = StreamProvider<List<Order>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return _streamStudentOrders(client, user.id);
});

Stream<List<Order>> _streamStudentOrders(
  SupabaseClient client,
  String userId,
) async* {
  Future<List<Order>> fetchOrders() async {
    final rows = await client
        .from('orders')
        .select()
        .eq('student_id', userId)
        .order('created_at', ascending: false);
    return _attachVendorNames(client, rows);
  }

  yield await fetchOrders();

  try {
    final stream = client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('student_id', userId)
        .order('created_at', ascending: false);

    await for (final _ in stream) {
      yield await fetchOrders();
    }
  } catch (_) {
    // Realtime failed; initial data is already showing.
  }
}

/// `.stream()` returns raw table rows with no join support, so vendor
/// names are batch-fetched per emission and folded in the same shape the
/// old `select('*, vendors(name)')` produced, keeping `Order.fromMap`
/// unchanged.
Future<List<Order>> _attachVendorNames(
  SupabaseClient client,
  List<Map<String, dynamic>> rows,
) async {
  final vendorIds =
      rows.map((m) => m['vendor_id']).whereType<String>().toSet().toList();

  final namesById = <String, String>{};
  if (vendorIds.isNotEmpty) {
    final vendors = await client
        .from('vendors')
        .select('id, name')
        .inFilter('id', vendorIds);
    for (final v in vendors) {
      namesById[v['id'] as String] = v['name'] as String;
    }
  }

  return rows.map((m) {
    final vendorId = m['vendor_id'] as String?;
    final withVendor = {
      ...m,
      if (vendorId != null && namesById[vendorId] != null)
        'vendors': {'name': namesById[vendorId]},
    };
    return Order.fromMap(withVendor);
  }).toList();
}

/// Delivery groups for the signed-in student, newest first, live via
/// Supabase Realtime. Used by the orders screen to show multi-vendor
/// checkouts as a single entry.
final studentDeliveryGroupsProvider =
    StreamProvider<List<DeliveryGroup>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return _streamStudentDeliveryGroups(client, user.id);
});

Stream<List<DeliveryGroup>> _streamStudentDeliveryGroups(
  SupabaseClient client,
  String userId,
) async* {
  Future<List<DeliveryGroup>> fetchGroups() async {
    final rows = await client
        .from('delivery_groups')
        .select()
        .eq('student_id', userId)
        .order('created_at', ascending: false);
    return rows.map((m) => DeliveryGroup.fromMap(m)).toList();
  }

  yield await fetchGroups();

  try {
    final stream = client
        .from('delivery_groups')
        .stream(primaryKey: ['id'])
        .eq('student_id', userId)
        .order('created_at', ascending: false);

    await for (final _ in stream) {
      yield await fetchGroups();
    }
  } catch (_) {
    // Realtime failed; initial data is already showing.
  }
}

/// A unified entry for the student orders screen — either a standalone
/// Order (pickup / errand) or a DeliveryGroup (delivery orders).
class StudentOrderEntry {
  const StudentOrderEntry.fromOrder(this.order)
      : group = null,
        gift = null;
  const StudentOrderEntry.fromGroup(this.group)
      : order = null,
        gift = null;

  /// A gift this student RECEIVES (recipient-only mirror; no prices).
  const StudentOrderEntry.fromGift(this.gift)
      : order = null,
        group = null;

  final Order? order;
  final DeliveryGroup? group;
  final GiftDelivery? gift;

  bool get isGroup => group != null;
  bool get isGift => gift != null;
  String get id => isGift ? gift!.groupId : (isGroup ? group!.id : order!.id);
  String get shortId =>
      isGift ? gift!.shortId : (isGroup ? group!.shortId : order!.shortId);
  DateTime get createdAt => isGift
      ? gift!.createdAt
      : (isGroup ? group!.createdAt : order!.createdAt);

  bool get isTerminal => isGift
      ? gift!.isEnded
      : (isGroup ? group!.isTerminal : order!.status.isTerminal);

  bool get isActive => !isTerminal;

  String get statusLabel {
    if (isGift) return gift!.statusLabel;
    if (isGroup) return group!.status.label;
    return order!.status.label;
  }
}

/// A single delivery group by ID, live via Supabase Realtime. Used by
/// the group tracking screen.
final groupByIdProvider =
    StreamProvider.family<DeliveryGroup?, String>((ref, groupId) {
  final client = ref.watch(supabaseClientProvider);
  return _streamGroupById(client, groupId);
});

Stream<DeliveryGroup?> _streamGroupById(
  SupabaseClient client,
  String groupId,
) async* {
  Future<DeliveryGroup?> fetch() async {
    final rows = await client
        .from('delivery_groups')
        .select()
        .eq('id', groupId)
        .limit(1);
    if (rows.isEmpty) return null;
    return DeliveryGroup.fromMap(rows.first);
  }

  yield await fetch();

  try {
    final stream = client
        .from('delivery_groups')
        .stream(primaryKey: ['id']).eq('id', groupId);

    await for (final _ in stream) {
      yield await fetch();
    }
  } catch (_) {}
}

/// A single order by ID, live via Supabase Realtime, with its line items
/// populated. Used by the tracking screen — a Kitchen/rider status change
/// now reaches this screen without the student tapping refresh.
final orderByIdProvider = StreamProvider.family<Order?, String>((ref, orderId) {
  final client = ref.watch(supabaseClientProvider);
  return _streamOrderById(client, orderId);
});

Stream<Order?> _streamOrderById(SupabaseClient client, String orderId) async* {
  Future<Order?> fetchOrder() async {
    final rows =
        await client.from('orders').select().eq('id', orderId).limit(1);
    if (rows.isEmpty) return null;
    final withVendor = (await _attachVendorNames(client, [rows.first])).first;
    final items =
        await client.from('order_items').select().eq('order_id', orderId);
    return withVendor.copyWith(
      items: items.map((m) => OrderItem.fromMap(m)).toList(),
    );
  }

  yield await fetchOrder();

  try {
    final stream =
        client.from('orders').stream(primaryKey: ['id']).eq('id', orderId);

    await for (final _ in stream) {
      yield await fetchOrder();
    }
  } catch (_) {
    // Realtime failed; initial data is already showing.
  }
}

/// The assigned rider's name/phone for an order, once one exists
/// (post-testing fixes, Section 12 — mirrors get_customer_info, which
/// already gives the rider the student's contact the other way around).
/// Returns null until a rider has accepted.
final orderRiderInfoProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);
  final result =
      await client.rpc('get_rider_info', params: {'p_order_id': orderId});
  return result == null ? null : Map<String, dynamic>.from(result as Map);
});

// ---------------------------------------------------------------------------
// Delivery settings (Round 7 — admin-editable fees)
// ---------------------------------------------------------------------------

/// Fetches the delivery settings map from the server.
/// Keys: 'campus_delivery_fee', 'hostel_delivery_fee', 'pack_meal_capacity'.
final deliverySettingsProvider =
    FutureProvider<Map<String, String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('get_delivery_settings');
  final raw = Map<String, dynamic>.from(result as Map);
  return raw.map((k, v) => MapEntry(k, v.toString()));
});

/// Helper to extract the per-vendor delivery fee for a given delivery type.
double deliveryFeePerVendor(Map<String, String> settings, String deliveryType) {
  switch (deliveryType) {
    case 'campus_delivery':
      return double.tryParse(settings['campus_delivery_fee'] ?? '') ?? 200;
    case 'hostel_delivery':
      return double.tryParse(settings['hostel_delivery_fee'] ?? '') ?? 300;
    default:
      return 0;
  }
}

// ---------------------------------------------------------------------------
// Delivery locations (Round 8 — named locations with prices)
// ---------------------------------------------------------------------------

/// Active delivery locations from the `delivery_locations` table.
final deliveryLocationsProvider =
    FutureProvider<List<DeliveryLocation>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('get_delivery_locations');
  final rows = (result as List).cast<Map<String, dynamic>>();
  return rows.map((m) => DeliveryLocation.fromMap(m)).toList();
});

// ---------------------------------------------------------------------------
// Order creation lives in order_payment_repository.dart (Pack 4A): there is
// no "place the order now, pay later" path any more. packBrackets() and
// vendorDeliveryFee() moved to checkout_draft.dart.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Student cancel (A3 — before rider accepts)
// ---------------------------------------------------------------------------

/// Cancel a standalone order (errand / pickup) before a rider accepts.
/// Throws if the order is already terminal or a rider has taken it.
/// Invalidates [studentOrdersProvider] on success.
Future<void> cancelOrder(WidgetRef ref, String orderId) async {
  final client = ref.read(supabaseClientProvider);
  await client.rpc('student_cancel_order', params: {'p_order_id': orderId});
  ref.invalidate(studentOrdersProvider);
}

/// Cancel a multi-vendor delivery group before a rider accepts.
/// Invalidates [studentDeliveryGroupsProvider] on success.
Future<void> cancelDeliveryGroup(WidgetRef ref, String groupId) async {
  final client = ref.read(supabaseClientProvider);
  await client
      .rpc('student_cancel_delivery_group', params: {'p_group_id': groupId});
  ref.invalidate(studentDeliveryGroupsProvider);
}

/// Maps raw exception messages from cancel RPCs to user-facing strings.
String mapCancelError(String raw) {
  if (raw.contains('ORDER_ALREADY_ACCEPTED')) {
    return 'A rider has already accepted this order. You can no longer cancel it.';
  }
  if (raw.contains('ORDER_ALREADY_TERMINAL')) {
    return 'This order is already completed or cancelled.';
  }
  return 'Could not cancel. Please try again.';
}
