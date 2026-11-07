import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/errand_category.dart';
import '../../shared/models/order.dart';
import '../../shared/models/product.dart';
import '../../shared/models/advertisement.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import 'admin_service.dart';

/// Single shared instance of [AdminService].
final adminServiceProvider = Provider<AdminService>((ref) {
  return AdminService(ref.watch(supabaseClientProvider));
});

/// All vendors (active + inactive), for the admin management screens.
/// Refresh with `ref.invalidate(allVendorsProvider)` after a mutation.
final allVendorsProvider = FutureProvider<List<Vendor>>((ref) async {
  return ref.watch(adminServiceProvider).fetchAllVendors();
});

/// All products for a specific vendor, including unavailable items.
/// The family key is the vendor's UUID string.
final adminVendorProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, vendorId) async {
  return ref.watch(adminServiceProvider).fetchAllVendorProducts(vendorId);
});

/// Live kitchen queue: Uniflex orders in placed/preparing/ready states,
/// each paired with their line items. Uses Supabase Realtime — the orders
/// table must be in the `supabase_realtime` publication (see schema.sql).
final kitchenOrdersProvider = StreamProvider<List<KitchenOrder>>((ref) {
  return ref.watch(adminServiceProvider).streamKitchenOrders();
});

/// Today's dashboard metrics from `get_dashboard_stats()` (orders, pending,
/// completed, cancelled, fees collected, food payments). Refetched on tab
/// open, pull-to-refresh and when orders change — see `StatsLiveRefresh`.
final dashboardStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(adminServiceProvider).getDashboardStats();
});

/// Phase 6: live stream of upcoming scheduled orders for the admin
/// Scheduled Orders view.
final scheduledOrdersProvider = StreamProvider<List<Order>>((ref) {
  return ref.watch(adminServiceProvider).streamScheduledOrders();
});

/// Post-testing fixes, Section 7: all rider accounts for the Rider
/// Management screen. Refresh with `ref.invalidate(adminRidersProvider)`
/// after add/remove/activate.
final adminRidersProvider = FutureProvider<List<RiderAccount>>((ref) async {
  return ref.watch(adminServiceProvider).fetchRiders();
});

/// All Errand categories (active + inactive) for the admin management
/// screen under the Manage hub.
final adminErrandCategoriesProvider =
    FutureProvider<List<ErrandCategoryData>>((ref) async {
  return ref.watch(adminServiceProvider).fetchAllErrandCategories();
});

/// Phase 10: every referral code Admin has minted, with usage counts.
/// Refresh with `ref.invalidate(adminReferralCodesProvider)` after a change.
final adminReferralCodesProvider =
    FutureProvider<List<ReferralCodeRow>>((ref) async {
  return ref.watch(adminServiceProvider).fetchReferralCodes();
});

/// The signups attributed to one referral code. Family key is the code id.
final adminReferralCodeUsesProvider =
    FutureProvider.family<List<ReferralCodeUse>, String>((ref, codeId) async {
  return ref.watch(adminServiceProvider).fetchReferralCodeUses(codeId);
});

/// Phase 10: every advertisement, including paused/scheduled/expired ones.
final adminAdvertisementsProvider =
    FutureProvider<List<Advertisement>>((ref) async {
  return ref.watch(adminServiceProvider).fetchAllAdvertisements();
});

/// Analytics for the Admin Analytics screen from `get_admin_analytics()`.
final adminAnalyticsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(adminServiceProvider).getAnalytics();
});

/// Live stream of all non-terminal delivery groups (multi-vendor checkouts),
/// with vendor names and leg count. Used by the Deliveries tab.
final adminDeliveryGroupsProvider =
    StreamProvider<List<AdminDeliveryGroupRow>>((ref) {
  return ref.watch(adminServiceProvider).streamAllDeliveryGroups();
});

/// Live stream of all non-terminal errand orders, enriched with
/// errand_requests pickup + item data. Used by the Errands tab.
final adminErrandOrdersProvider = StreamProvider<List<AdminErrandRow>>((ref) {
  return ref.watch(adminServiceProvider).streamErrandOrders();
});
