import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/around_category.dart';
import '../../shared/models/order.dart';
import '../../shared/models/product.dart';
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
final kitchenOrdersProvider =
    StreamProvider<List<KitchenOrder>>((ref) {
  return ref.watch(adminServiceProvider).streamKitchenOrders();
});

/// Today's dashboard metrics (order counts, revenue, pending). Refreshed
/// manually via `ref.invalidate(dashboardStatsProvider)`.
final dashboardStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(adminServiceProvider).getDashboardStats();
});

/// Phase 6: live stream of upcoming scheduled orders for the admin
/// Scheduled Orders view.
final scheduledOrdersProvider =
    StreamProvider<List<Order>>((ref) {
  return ref.watch(adminServiceProvider).streamScheduledOrders();
});

/// Post-testing fixes, Section 7: all rider accounts for the Rider
/// Management screen. Refresh with `ref.invalidate(adminRidersProvider)`
/// after add/remove/activate.
final adminRidersProvider = FutureProvider<List<RiderAccount>>((ref) async {
  return ref.watch(adminServiceProvider).fetchRiders();
});

/// Post-testing fixes, Section 9: all Around categories (active +
/// inactive) for the admin management screen under the Manage hub.
final adminAroundCategoriesProvider =
    FutureProvider<List<AroundCategoryData>>((ref) async {
  return ref.watch(adminServiceProvider).fetchAllAroundCategories();
});
