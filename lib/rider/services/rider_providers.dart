import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/services/auth/auth_providers.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../delivery/delivery_record.dart';
import '../pool/pool_order.dart';
import 'rider_service.dart';

/// Single shared instance of [RiderService].
final riderServiceProvider = Provider<RiderService>((ref) {
  return RiderService(
    ref.watch(supabaseClientProvider),
    ref.watch(notificationInboxServiceProvider),
  );
});

/// Live stream of pool-eligible unassigned orders. Re-emits via Supabase
/// Realtime whenever any matching order row changes (new order placed,
/// order accepted by another rider, etc.).
final jobPoolProvider = StreamProvider<List<PoolOrder>>((ref) {
  return ref.watch(riderServiceProvider).streamJobPool();
});

/// Streams the rider's currently active delivery (out_for_delivery).
/// Emits null when the rider has no active order.
final activeDeliveryProvider = StreamProvider<Order?>((ref) {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  if (profile == null) return Stream.value(null);
  return ref.watch(riderServiceProvider).streamActiveDelivery(profile.id);
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

/// Enriched detail for the currently active delivery order: pickup name/
/// address and customer contact. Keyed by order-id so the
/// ActiveDeliveryScreen can watch it with `.family`.
final activeDeliveryDetailProvider =
    FutureProvider.family<ActiveDeliveryDetail?, String>((ref, orderId) async {
  final orderAsync = ref.watch(activeDeliveryProvider);
  final order = orderAsync.valueOrNull;
  if (order == null || order.id != orderId) return null;
  return ref.read(riderServiceProvider).fetchActiveDeliveryDetail(order);
});
