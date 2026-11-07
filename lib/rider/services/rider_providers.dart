import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/supabase/supabase_providers.dart';
import '../jobs/rider_job.dart';
import 'rider_service.dart';

/// Single shared instance of [RiderService].
final riderServiceProvider = Provider<RiderService>((ref) {
  return RiderService(ref.watch(supabaseClientProvider));
});

/// The Jobs tab: food deliveries + errands waiting to be accepted.
final riderPoolProvider = StreamProvider.autoDispose<RiderPool>((ref) {
  return ref.watch(riderServiceProvider).streamJobPool();
});

/// All of this rider's active jobs (food + errands), one entry per checkout.
final riderActiveJobsProvider =
    StreamProvider.autoDispose<List<RiderJob>>((ref) {
  return ref.watch(riderServiceProvider).streamActiveJobs();
});

/// Today + total stats, active counts and online status. Refresh with
/// `ref.invalidate(riderStatsProvider)`.
final riderStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(riderServiceProvider).getRiderStats();
});

/// Finished jobs (completed + cancelled), one entry per checkout.
final riderHistoryProvider =
    FutureProvider.autoDispose<List<RiderJob>>((ref) async {
  return ref.watch(riderServiceProvider).fetchHistory();
});

/// Read-only details of one finished job (also feeds "Delivery complete").
final riderHistoryItemProvider =
    FutureProvider.autoDispose.family<RiderJobDetail, String>((ref, id) {
  return ref.watch(riderServiceProvider).fetchHistoryItem(id);
});

/// Customer info for an accepted food job.
final groupCustomerInfoProvider = FutureProvider.autoDispose
    .family<GroupCustomerInfo, String>((ref, groupId) {
  return ref.read(riderServiceProvider).getGroupCustomerInfo(groupId);
});

/// Customer name + phone for a live errand.
final errandCustomerProvider =
    FutureProvider.autoDispose.family<ErrandCustomer, String>((ref, id) {
  return ref.read(riderServiceProvider).fetchErrandCustomer(id);
});

/// Live stream of a single delivery group by ID.
final groupDetailProvider = StreamProvider.autoDispose
    .family<RiderGroupDetail?, String>((ref, groupId) {
  return ref.watch(riderServiceProvider).streamGroupDetail(groupId);
});
