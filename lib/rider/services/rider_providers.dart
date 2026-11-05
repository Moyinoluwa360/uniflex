import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/delivery_group.dart';
import '../../shared/models/order.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../delivery/delivery_record.dart';
import '../pool/pool_group.dart';
import '../pool/pool_order.dart';
import 'rider_service.dart';

// ignore_for_file: unused_element

/// Single shared instance of [RiderService].
final riderServiceProvider = Provider<RiderService>((ref) {
  return RiderService(
    ref.watch(supabaseClientProvider),
    ref.watch(notificationInboxServiceProvider),
  );
});

/// Unified pool: delivery groups + errand orders.
final poolProvider =
    StreamProvider<({List<PoolGroup> groups, List<PoolOrder> errands})>((ref) {
  return ref.watch(riderServiceProvider).streamPool();
});

/// Backward-compat alias: expose just the groups from the unified pool.
final groupPoolProvider = StreamProvider<List<PoolGroup>>((ref) {
  final pool = ref.watch(poolProvider).valueOrNull;
  return Stream.value(pool?.groups ?? []);
});

/// Active work: delivery groups + errand orders assigned to this rider.
final activeWorkProvider = StreamProvider<
    ({List<DeliveryGroup> groups, List<Order> errands})>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) {
    return Stream.value((groups: <DeliveryGroup>[], errands: <Order>[]));
  }
  return ref.watch(riderServiceProvider).streamActiveWork(profile.id);
});

/// Backward-compat alias: expose just the errands from activeWorkProvider.
final activeDeliveriesProvider = StreamProvider<List<Order>>((ref) {
  final work = ref.watch(activeWorkProvider).valueOrNull;
  return Stream.value(work?.errands ?? []);
});

/// Today + total delivery stats, plus online status. Refresh with
/// `ref.invalidate(riderStatsProvider)` after toggling online or completing.
final riderStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(riderServiceProvider).getRiderStats();
});

/// Full delivery history for the current rider, newest first.
final deliveryHistoryProvider =
    FutureProvider<List<DeliveryRecord>>((ref) async {
  return ref.watch(riderServiceProvider).fetchDeliveryHistory();
});

/// Enriched detail for a specific active delivery order: pickup name/
/// address and customer contact. Keyed by order-id so the
/// ActiveDeliveryScreen can watch it with `.family`.
final activeDeliveryDetailProvider =
    FutureProvider.family<ActiveDeliveryDetail?, String>((ref, orderId) async {
  final work = ref.watch(activeWorkProvider).valueOrNull;
  final orders = work?.errands ?? [];
  final order = orders.where((o) => o.id == orderId).firstOrNull;
  if (order == null) return null;
  return ref.read(riderServiceProvider).fetchActiveDeliveryDetail(order);
});

/// Full items for a delivery group. FutureProvider.family keyed by group ID.
final groupItemsProvider =
    FutureProvider.family<List<GroupVendorItems>, String>((ref, groupId) {
  return ref.read(riderServiceProvider).getGroupItems(groupId);
});

/// Customer info for an accepted group. FutureProvider.family keyed by group ID.
final groupCustomerInfoProvider =
    FutureProvider.family<GroupCustomerInfo, String>((ref, groupId) {
  return ref.read(riderServiceProvider).getGroupCustomerInfo(groupId);
});

/// Live stream of a single delivery group by ID. Used by GroupDeliveryScreen.
final groupDetailProvider =
    StreamProvider.family<DeliveryGroup?, String>((ref, groupId) {
  return ref.watch(riderServiceProvider).streamGroupDetail(groupId);
});

/// Order legs for a delivery group. Invalidate to re-fetch after
/// confirming a leg pickup.
final groupLegsProvider =
    FutureProvider.family<List<Order>, String>((ref, groupId) async {
  return ref.read(riderServiceProvider).fetchGroupLegs(groupId);
});
