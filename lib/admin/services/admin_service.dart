import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/around_category.dart';
import '../../shared/models/order.dart';
import '../../shared/models/order_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';

/// One row from `admin_list_riders()` — a rider account as Admin sees it
/// in the Rider Management screen (post-testing fixes, Section 7).
class RiderAccount {
  const RiderAccount({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.isActive,
    required this.isOnline,
    required this.createdAt,
  });

  factory RiderAccount.fromMap(Map<String, dynamic> map) {
    return RiderAccount(
      id: map['id'] as String,
      fullName: map['full_name'] as String? ?? '—',
      email: map['email'] as String? ?? '—',
      phone: map['phone'] as String?,
      isActive: map['is_active'] as bool? ?? true,
      isOnline: map['rider_is_online'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  final String id;
  final String fullName;
  final String email;
  final String? phone;
  final bool isActive;
  final bool isOnline;
  final DateTime createdAt;
}

/// Thrown when the `admin-create-rider` Edge Function rejects a request
/// (e.g. duplicate email), with a message safe to show directly to Admin.
class AdminException implements Exception {
  AdminException(this.message);
  final String message;

  @override
  String toString() => 'AdminException: $message';
}

/// A kitchen order: an active Uniflex-source order (placed/preparing/ready)
/// together with its resolved line items. Used exclusively by the Kitchen
/// Queue screen — not a shared model.
class KitchenOrder {
  const KitchenOrder({required this.order, required this.items});

  final Order order;
  final List<OrderItem> items;
}

/// Service wrapping all Supabase calls made by admin-only screens.
///
/// Security model: every mutation goes through either a direct
/// authenticated client call protected by admin-only RLS policies (see
/// Phase 4 block in supabase/schema.sql), or a SECURITY DEFINER RPC that
/// checks `is_admin()` itself. No client-side role check is needed in
/// this service — a non-admin JWT would be rejected by the server.
class AdminService {
  const AdminService(this._client);

  final SupabaseClient _client;

  // ── Vendors ─────────────────────────────────────────────────────────

  /// All vendors (active and inactive), ordered with Uniflex first then
  /// alphabetically. Includes partner vendors not shown to students.
  Future<List<Vendor>> fetchAllVendors() async {
    final data = await _client
        .from('vendors')
        .select()
        .order('is_featured', ascending: false)
        .order('name');
    return data.map((m) => Vendor.fromMap(m)).toList();
  }

  /// Insert a new vendor (id == null) or update an existing one.
  Future<void> upsertVendor({
    String? id,
    required String name,
    required String description,
    required bool isActive,
    String? badgeLabel,
    String? imageUrl,
    String? location,
    String? contact,
    double? packPrice,
  }) async {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
      'is_active': isActive,
      'badge_label': badgeLabel,
      'image_url': imageUrl,
      'location': location,
      'contact': contact,
      if (packPrice != null) 'pack_price': packPrice,
    };
    if (id != null) {
      await _client.from('vendors').update(map).eq('id', id);
    } else {
      await _client.from('vendors').insert(map);
    }
  }

  /// Hard-delete a vendor row. Cascades to products via the FK constraint.
  /// Use with caution — prefer deactivating (isActive = false) instead.
  Future<void> deleteVendor(String id) async {
    await _client.from('vendors').delete().eq('id', id);
  }

  // ── Products ─────────────────────────────────────────────────────────

  /// All products for [vendorId], including unavailable items (so admin
  /// can toggle availability). Ordered by category then name.
  Future<List<Product>> fetchAllVendorProducts(String vendorId) async {
    final data = await _client
        .from('products')
        .select()
        .eq('vendor_id', vendorId)
        .order('category')
        .order('name');
    return data.map((m) => Product.fromMap(m)).toList();
  }

  /// Insert a new product (id == null) or update an existing one.
  Future<void> upsertProduct({
    String? id,
    required String vendorId,
    required String name,
    required String description,
    required String category,
    required double basePrice,
    String? imageUrl,
    bool isAvailable = true,
    bool requiresPack = false,
  }) async {
    final map = <String, dynamic>{
      'vendor_id': vendorId,
      'name': name,
      'description': description,
      'category': category,
      'base_price': basePrice,
      'image_url': imageUrl,
      'is_available': isAvailable,
      'requires_pack': requiresPack,
    };
    if (id != null) {
      await _client.from('products').update(map).eq('id', id);
    } else {
      await _client.from('products').insert(map);
    }
  }

  /// Hard-delete a product. Also removes its product_options via cascade.
  Future<void> deleteProduct(String id) async {
    await _client.from('products').delete().eq('id', id);
  }

  /// Upload [bytes] to the `product-images` storage bucket, returning
  /// the public URL on success. [fileName] should include a unique
  /// component (e.g. a UUID) to avoid collisions.
  ///
  /// Requires the `product-images` bucket to exist and have the admin
  /// upload policy applied (see schema.sql Phase 4 Storage section).
  Future<String> uploadProductImage(Uint8List bytes, String fileName) async {
    final path = 'products/$fileName';
    await _client.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('product-images').getPublicUrl(path);
  }

  // ── Kitchen Queue ─────────────────────────────────────────────────────

  /// A live stream of active Uniflex kitchen orders (status: placed,
  /// preparing, ready), newest first. Each emission includes the line
  /// items fetched in a single batch query so the kitchen can see what to
  /// prepare. The stream re-emits whenever any `orders` row changes via
  /// Supabase Realtime (requires the table to be in the
  /// `supabase_realtime` publication — see schema.sql Phase 4 block).
  Stream<List<KitchenOrder>> streamKitchenOrders() async* {
    final orderStream = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('source', 'uniflex')
        .order('created_at', ascending: false);

    await for (final rows in orderStream) {
      // Filter to active kitchen stages client-side.
      final active = rows
          .where((m) =>
              const ['placed', 'preparing', 'ready'].contains(m['status']))
          .toList();

      if (active.isEmpty) {
        yield [];
        continue;
      }

      final ids = active.map((m) => m['id'] as String).toList();

      // Batch-fetch items for all active orders in one round trip.
      final itemsData = await _client
          .from('order_items')
          .select()
          .inFilter('order_id', ids);

      final itemsByOrder = <String, List<OrderItem>>{};
      for (final m in itemsData) {
        final item = OrderItem.fromMap(m);
        itemsByOrder.putIfAbsent(item.orderId, () => []).add(item);
      }

      yield active.map((m) {
        final order = Order.fromMap(m);
        return KitchenOrder(
          order: order,
          items: itemsByOrder[order.id] ?? [],
        );
      }).toList();
    }
  }

  /// Advance (or revert) an order's status. Calls the `update_order_status`
  /// SECURITY DEFINER RPC, which verifies the caller is an admin.
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _client.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': newStatus,
    });
  }

  // ── Rider management (post-testing fixes, Section 7) ───────────────────

  /// All rider accounts, active and inactive, via the admin_list_riders()
  /// RPC (profiles has no admin SELECT-all policy, so this can't be a
  /// plain table select).
  Future<List<RiderAccount>> fetchRiders() async {
    final data = await _client.rpc('admin_list_riders');
    return (data as List)
        .map((m) => RiderAccount.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  /// Soft "remove"/"deactivate" (and reversible "reactivate") — never
  /// deletes the rider's account or delivery history, only flips whether
  /// they can sign in and appear in the active roster.
  Future<void> setRiderActive(String riderId, bool active) async {
    await _client.rpc('admin_set_rider_active', params: {
      'p_rider_id': riderId,
      'p_active': active,
    });
  }

  /// Invites a new Rider account. Invite-only, consistent with the Phase 1
  /// pattern (no public Rider signup path) — this just moves "seed the
  /// account by hand in Supabase" into an in-app action for Admin, via the
  /// `admin-create-rider` Edge Function (needs a service-role key, which
  /// this Dart client never holds).
  Future<void> createRider({
    required String email,
    required String password,
    required String fullName,
    String? phone,
  }) async {
    try {
      final res = await _client.functions.invoke('admin-create-rider', body: {
        'email': email,
        'password': password,
        'full_name': fullName,
        'phone': phone,
      });
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw AdminException(data['error'].toString());
      }
    } on FunctionException catch (e) {
      final body = e.details;
      final message = body is Map && body['error'] != null
          ? body['error'].toString()
          : 'Could not create rider (${e.status}).';
      throw AdminException(message);
    }
  }

  // ── Around categories (post-testing fixes, Section 9) ───────────────────

  /// All Around categories, active and inactive, for the admin management
  /// screen. Students only ever see the active ones (see
  /// activeAroundCategoriesProvider).
  Future<List<AroundCategoryData>> fetchAllAroundCategories() async {
    final data = await _client
        .from('around_categories')
        .select()
        .order('sort_order');
    return data.map((m) => AroundCategoryData.fromMap(m)).toList();
  }

  /// Insert a new category (id == null) or update an existing one. [key]
  /// is only used on insert — it's the stable identifier `around_requests`
  /// rows reference, so it's never edited afterwards.
  Future<void> upsertAroundCategory({
    String? id,
    String? key,
    required String title,
    required String subtitle,
    required String description,
    required String iconName,
    required double flatFee,
    required bool isActive,
    required int sortOrder,
  }) async {
    final map = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'description': description,
      'icon_name': iconName,
      'flat_fee': flatFee,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
    if (id != null) {
      await _client.from('around_categories').update(map).eq('id', id);
    } else {
      await _client.from('around_categories').insert({
        ...map,
        'key': key,
      });
    }
  }

  /// Hard-delete a category. Blocked by the `around_requests` foreign key
  /// if any past request used it — deactivate instead in that case.
  Future<void> deleteAroundCategory(String id) async {
    await _client.from('around_categories').delete().eq('id', id);
  }

  // ── Dashboard ─────────────────────────────────────────────────────────

  /// Returns today's key metrics: order counts by status, pending count,
  /// and Uniflex revenue. Calls the `get_dashboard_stats` SECURITY DEFINER
  /// RPC, which verifies the caller is an admin.
  Future<Map<String, dynamic>> getDashboardStats() async {
    final result = await _client.rpc('get_dashboard_stats');
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Phase 6: Scheduled Orders ─────────────────────────────────────────

  /// Live stream of upcoming scheduled orders (scheduled_for IS NOT NULL,
  /// status in placed/preparing), ordered by scheduled_for ascending.
  /// Uses Supabase Realtime on the orders table.
  Stream<List<Order>> streamScheduledOrders() async* {
    final stream = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .order('scheduled_for', ascending: true);

    await for (final rows in stream) {
      yield rows
          .where((m) =>
              m['scheduled_for'] != null &&
              const ['placed', 'preparing'].contains(m['status']))
          .map((m) => Order.fromMap(m))
          .toList();
    }
  }
}
