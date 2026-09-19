import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/order.dart';
import '../../shared/models/order_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';

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
  }) async {
    final map = <String, dynamic>{
      'name': name,
      'description': description,
      'is_active': isActive,
      'badge_label': badgeLabel,
      'image_url': imageUrl,
      'location': location,
      'contact': contact,
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
  }) async {
    final map = <String, dynamic>{
      'vendor_id': vendorId,
      'name': name,
      'description': description,
      'category': category,
      'base_price': basePrice,
      'image_url': imageUrl,
      'is_available': isAvailable,
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
