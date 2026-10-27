import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/advertisement.dart';
import '../../shared/models/around_category.dart';
import '../../shared/models/order.dart';
import '../../shared/models/order_item.dart';
import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/notifications/notification_inbox_service.dart';

/// A referral code as Admin sees it, with how many signups have used it.
class ReferralCodeRow {
  const ReferralCodeRow({
    required this.id,
    required this.code,
    required this.isActive,
    required this.useCount,
    required this.createdAt,
    this.ownerId,
    this.ownerName,
    this.ownerLabel,
    this.note,
  });

  factory ReferralCodeRow.fromMap(Map<String, dynamic> map) {
    return ReferralCodeRow(
      id: map['id'] as String,
      code: map['code'] as String,
      isActive: map['is_active'] as bool? ?? true,
      useCount: (map['use_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      ownerId: map['owner_id'] as String?,
      ownerName: map['owner_name'] as String?,
      ownerLabel: map['owner_label'] as String?,
      note: map['note'] as String?,
    );
  }

  final String id;
  final String code;
  final bool isActive;
  final int useCount;
  final DateTime createdAt;

  /// Set when the code is held by an app user — that user earns the referral
  /// bonus. Null for a code given to someone with no account.
  final String? ownerId;
  final String? ownerName;
  final String? ownerLabel;
  final String? note;

  /// Who this code was allocated to, however that was recorded.
  String get allocatedTo => ownerName ?? ownerLabel ?? 'Unallocated';

  /// True when nobody earns the bonus from this code's signups.
  bool get earnsNobodyBonus => ownerId == null;
}

/// A student as returned by `admin_search_students()`, for the allocate
/// picker on the referral-code form.
class StudentPick {
  const StudentPick({
    required this.id,
    required this.displayName,
    this.matricNumber,
    this.email,
  });

  factory StudentPick.fromMap(Map<String, dynamic> map) {
    return StudentPick(
      id: map['id'] as String,
      displayName: map['display_name'] as String? ?? '—',
      matricNumber: map['matric_number'] as String?,
      email: map['email'] as String?,
    );
  }

  final String id;
  final String displayName;
  final String? matricNumber;
  final String? email;
}

/// One signup attributed to a referral code.
class ReferralCodeUse {
  const ReferralCodeUse({
    required this.referredName,
    required this.usedAt,
    this.matricNumber,
  });

  factory ReferralCodeUse.fromMap(Map<String, dynamic> map) {
    return ReferralCodeUse(
      referredName: map['referred_name'] as String? ?? '—',
      usedAt: DateTime.parse(map['used_at'] as String).toLocal(),
      matricNumber: map['matric_number'] as String?,
    );
  }

  final String referredName;
  final DateTime usedAt;
  final String? matricNumber;
}

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
  const AdminService(this._client, this._notifications);

  final SupabaseClient _client;

  /// Used to tell the customer about status changes. Injected rather than
  /// constructed here so the "who may notify whom" rule stays in one place.
  final NotificationInboxService _notifications;

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
  /// prepare.
  ///
  /// Emits an initial fetch immediately, then subscribes to Supabase
  /// Realtime for live updates. If Realtime hangs or fails the initial
  /// data still shows.
  Stream<List<KitchenOrder>> streamKitchenOrders() async* {
    // Helper: fetch active kitchen orders via a one-shot REST query.
    Future<List<KitchenOrder>> fetchKitchenOrders() async {
      final rows = await _client
          .from('orders')
          .select()
          .eq('source', 'uniflex')
          .order('created_at', ascending: false);

      final now = DateTime.now();
      final active = rows.where((m) {
        if (m['type'] != 'food') return false;
        if (!const [
          'being_sourced',           // commitment fee paid — kitchen starts here
          'placed',
          'preparing',
          'awaiting_final_payment',  // kitchen marked ready — student pays food cost
          'ready',
          'ready_for_pickup',
          'out_for_delivery',
        ].contains(m['status'])) {
          return false;
        }
        final scheduledFor = m['scheduled_for'] as String?;
        if (scheduledFor != null) {
          final due = DateTime.tryParse(scheduledFor)?.toLocal();
          if (due != null && due.isAfter(now)) return false;
        }
        return true;
      }).toList();

      if (active.isEmpty) return [];

      final ids = active.map((m) => m['id'] as String).toList();
      final itemsData = await _client
          .from('order_items')
          .select()
          .inFilter('order_id', ids);

      final itemsByOrder = <String, List<OrderItem>>{};
      for (final m in itemsData) {
        final item = OrderItem.fromMap(m);
        itemsByOrder.putIfAbsent(item.orderId, () => []).add(item);
      }

      return active.map((m) {
        final order = Order.fromMap(m);
        return KitchenOrder(
          order: order,
          items: itemsByOrder[order.id] ?? [],
        );
      }).toList();
    }

    // Emit initial data immediately so the screen is never blank.
    try {
      final initial = await fetchKitchenOrders();
      debugPrint('[KitchenQueue] Initial fetch: ${initial.length} orders');
      yield initial;
    } catch (e, st) {
      debugPrint('[KitchenQueue] Initial fetch FAILED: $e\n$st');
      yield [];
    }

    // Then subscribe to Realtime changes and re-fetch on every change.
    try {
      final orderStream = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('source', 'uniflex')
          .order('created_at', ascending: false);

      await for (final _ in orderStream) {
        try {
          final updated = await fetchKitchenOrders();
          debugPrint('[KitchenQueue] Realtime update: ${updated.length} orders');
          yield updated;
        } catch (e) {
          debugPrint('[KitchenQueue] Realtime fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[KitchenQueue] Realtime stream error: $e');
    }
  }

  /// Advance (or revert) an order's status. Calls the `update_order_status`
  /// SECURITY DEFINER RPC, which verifies the caller is an admin and (as
  /// of the post-testing fixes, Section 12) rejects jumping a delivery
  /// order straight to out_for_delivery/completed — those only happen via
  /// the rider workflow.
  Future<void> updateOrderStatus(String orderId, String newStatus) async {
    await _client.rpc('update_order_status', params: {
      'p_order_id': orderId,
      'p_new_status': newStatus,
    });
    // Tell the customer. Deliberately after the RPC and non-throwing: the
    // status change has already committed, so a failed push must not make
    // the kitchen think the change did not stick.
    await _notifications.notifyOrderStatus(orderId);
  }

  /// The "Transfer to Rider" action (Section 12) — explicitly pushes a
  /// Ready Uniflex delivery order into the rider job pool, rather than
  /// relying on an implicit status side-effect. Calls the
  /// `transfer_order_to_rider` SECURITY DEFINER RPC (admin-only).
  Future<void> transferOrderToRider(String orderId) async {
    await _client.rpc('transfer_order_to_rider', params: {
      'p_order_id': orderId,
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

  // ── Referral codes (Phase 10) ─────────────────────────────────────────

  /// Every code Admin has minted, newest first, with usage counts.
  Future<List<ReferralCodeRow>> fetchReferralCodes() async {
    final rows = await _client.rpc('admin_list_referral_codes');
    return (rows as List)
        .map((m) => ReferralCodeRow.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  /// Mints a new code. [ownerId] is the student who will earn the referral
  /// bonus; pass [ownerLabel] instead when the holder has no account.
  Future<void> createReferralCode({
    required String code,
    String? ownerId,
    String? ownerLabel,
    String? note,
  }) async {
    try {
      await _client.rpc('admin_create_referral_code', params: {
        'p_code': code,
        'p_owner_id': ownerId,
        'p_owner_label': ownerLabel,
        'p_note': note,
      });
    } on PostgrestException catch (e) {
      throw AdminException(_mapReferralError(e.message));
    }
  }

  Future<void> updateReferralCode({
    required String codeId,
    String? ownerId,
    String? ownerLabel,
    String? note,
    bool? isActive,
  }) async {
    try {
      await _client.rpc('admin_update_referral_code', params: {
        'p_code_id': codeId,
        'p_owner_id': ownerId,
        'p_owner_label': ownerLabel,
        'p_note': note,
        'p_is_active': isActive,
      });
    } on PostgrestException catch (e) {
      throw AdminException(_mapReferralError(e.message));
    }
  }

  Future<void> deleteReferralCode(String codeId) async {
    try {
      await _client
          .rpc('admin_delete_referral_code', params: {'p_code_id': codeId});
    } on PostgrestException catch (e) {
      throw AdminException(_mapReferralError(e.message));
    }
  }

  Future<List<ReferralCodeUse>> fetchReferralCodeUses(String codeId) async {
    final rows = await _client
        .rpc('admin_referral_code_uses', params: {'p_code_id': codeId});
    return (rows as List)
        .map((m) => ReferralCodeUse.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  Future<List<StudentPick>> searchStudents(String query) async {
    final rows =
        await _client.rpc('admin_search_students', params: {'p_query': query});
    return (rows as List)
        .map((m) => StudentPick.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  String _mapReferralError(String raw) {
    if (raw.contains('CODE_TAKEN')) {
      return 'That code is already in use. Pick another.';
    }
    if (raw.contains('CODE_FORMAT')) {
      return 'Codes must be 4–16 characters, letters and numbers only.';
    }
    if (raw.contains('CODE_IN_USE')) {
      return 'People have already signed up with this code, so it cannot be '
          'deleted. Pause it instead.';
    }
    if (raw.contains('OWNER_NOT_FOUND')) return 'That student no longer exists.';
    if (raw.contains('CODE_NOT_FOUND')) return 'That code no longer exists.';
    return raw;
  }

  // ── Advertisements (Phase 10) ─────────────────────────────────────────

  /// Every ad, including paused, scheduled, and expired ones (the read
  /// policy gives admin the full table; students see only live ads).
  Future<List<Advertisement>> fetchAllAdvertisements() async {
    final rows = await _client
        .from('advertisements')
        .select()
        .order('sort_order')
        .order('created_at', ascending: false);
    return rows.map((m) => Advertisement.fromMap(m)).toList();
  }

  Future<void> upsertAdvertisement({
    String? id,
    required String title,
    required String subtitle,
    required bool isDark,
    required bool isActive,
    required int sortOrder,
    String? imageUrl,
    AdLinkType linkType = AdLinkType.none,
    String? linkValue,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final map = <String, dynamic>{
      'title': title,
      'subtitle': subtitle,
      'is_dark': isDark,
      'is_active': isActive,
      'sort_order': sortOrder,
      'image_url': imageUrl,
      'link_type': linkType.name,
      'link_value': linkType == AdLinkType.none ? null : linkValue,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
    };
    if (id != null) {
      await _client.from('advertisements').update(map).eq('id', id);
    } else {
      await _client.from('advertisements').insert(map);
    }
  }

  Future<void> deleteAdvertisement(String id) async {
    await _client.from('advertisements').delete().eq('id', id);
  }

  /// Uploads an ad image into the existing product-images bucket, under its
  /// own prefix so ad art and menu photos stay separable.
  Future<String> uploadAdImage(Uint8List bytes, String fileName) async {
    final path = 'ads/$fileName';
    await _client.storage.from('product-images').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    return _client.storage.from('product-images').getPublicUrl(path);
  }

  // ── Dashboard ─────────────────────────────────────────────────────────

  /// Returns today's key metrics: order counts by status, pending count,
  /// and Uniflex revenue. Calls the `get_dashboard_stats` SECURITY DEFINER
  /// RPC, which verifies the caller is an admin.
  Future<Map<String, dynamic>> getDashboardStats() async {
    final result = await _client.rpc('get_dashboard_stats');
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Analytics ──────────────────────────────────────────────────────────

  /// Aggregate analytics data for the admin Analytics screen.
  /// Returns a map with: totalStudents, totalRiders, ordersToday,
  /// ordersThisWeek, ordersThisMonth, revenueToday, revenueThisWeek,
  /// revenueThisMonth, completedCount, cancelledCount, topItems,
  /// riderPerformance, and byStatus breakdown.
  Future<Map<String, dynamic>> getAnalytics() async {
    final now = DateTime.now().toUtc();
    final startOfDay = DateTime.utc(now.year, now.month, now.day);
    final startOfWeek = startOfDay.subtract(
        Duration(days: startOfDay.weekday - 1)); // ISO Monday
    final startOfMonth = DateTime.utc(now.year, now.month, 1);

    // User counts
    final studentRows = await _client
        .from('profiles')
        .select('id')
        .eq('role', 'student');
    final riderRows = await _client
        .from('profiles')
        .select('id')
        .eq('role', 'rider');

    // Orders for this month (superset of week/today)
    final monthOrders = await _client
        .from('orders')
        .select('id, status, total_amount, created_at, rider_id')
        .gte('created_at', startOfMonth.toIso8601String());

    // Aggregate
    int ordersToday = 0, ordersWeek = 0;
    double revToday = 0, revWeek = 0, revMonth = 0;
    int completed = 0, cancelled = 0;
    final statusCounts = <String, int>{};
    final itemFreq = <String, int>{};
    final riderDeliveries = <String, int>{};

    for (final row in monthOrders) {
      final createdAt = DateTime.parse(row['created_at'] as String);
      final amount = (row['total_amount'] as num).toDouble();
      final status = row['status'] as String;
      final riderId = row['rider_id'] as String?;

      revMonth += amount;
      if (createdAt.isAfter(startOfWeek)) {
        ordersWeek++;
        revWeek += amount;
      }
      if (createdAt.isAfter(startOfDay)) {
        ordersToday++;
        revToday += amount;
      }
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
      if (status == 'completed') {
        completed++;
        if (riderId != null) {
          riderDeliveries[riderId] = (riderDeliveries[riderId] ?? 0) + 1;
        }
      }
      if (status == 'cancelled') cancelled++;
    }

    // Top-selling items (this month's completed order items)
    final completedIds = monthOrders
        .where((r) => r['status'] == 'completed')
        .map((r) => r['id'] as String)
        .toList();

    if (completedIds.isNotEmpty) {
      final itemRows = await _client
          .from('order_items')
          .select('product_name, quantity')
          .inFilter('order_id', completedIds.take(200).toList());
      for (final ir in itemRows) {
        final name = ir['product_name'] as String;
        final qty = ir['quantity'] as int? ?? 1;
        itemFreq[name] = (itemFreq[name] ?? 0) + qty;
      }
    }

    // Sort top items
    final topItems = itemFreq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Rider performance — resolve names
    final riderPerf = <Map<String, dynamic>>[];
    if (riderDeliveries.isNotEmpty) {
      final riderIds = riderDeliveries.keys.toList();
      final riderProfiles = await _client
          .from('profiles')
          .select('id, full_name')
          .inFilter('id', riderIds);
      final nameMap = {
        for (final r in riderProfiles)
          r['id'] as String: r['full_name'] as String? ?? 'Unknown'
      };
      for (final entry in riderDeliveries.entries) {
        riderPerf.add({
          'name': nameMap[entry.key] ?? 'Unknown',
          'deliveries': entry.value,
        });
      }
      riderPerf.sort(
          (a, b) => (b['deliveries'] as int).compareTo(a['deliveries'] as int));
    }

    return {
      'totalStudents': studentRows.length,
      'totalRiders': riderRows.length,
      'ordersToday': ordersToday,
      'ordersThisWeek': ordersWeek,
      'ordersThisMonth': monthOrders.length,
      'revenueToday': revToday,
      'revenueThisWeek': revWeek,
      'revenueThisMonth': revMonth,
      'completedCount': completed,
      'cancelledCount': cancelled,
      'byStatus': statusCounts,
      'topItems': topItems.take(10).map((e) => {
            'name': e.key,
            'quantity': e.value,
          }).toList(),
      'riderPerformance': riderPerf,
    };
  }

  // ── Phase 6: Scheduled Orders ─────────────────────────────────────────

  /// Live stream of upcoming scheduled orders (scheduled_for IS NOT NULL,
  /// status in placed/preparing), ordered by scheduled_for ascending.
  Stream<List<Order>> streamScheduledOrders() async* {
    Future<List<Order>> fetchScheduled() async {
      final rows = await _client
          .from('orders')
          .select()
          .not('scheduled_for', 'is', null)
          .inFilter('status', ['placed', 'preparing'])
          .order('scheduled_for', ascending: true);
      return rows.map((m) => Order.fromMap(m)).toList();
    }

    // Emit initial data immediately.
    try {
      yield await fetchScheduled();
    } catch (e) {
      debugPrint('[ScheduledOrders] Initial fetch FAILED: $e');
      yield [];
    }

    // Then subscribe to Realtime for live updates.
    try {
      final stream = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .order('scheduled_for', ascending: true);

      await for (final _ in stream) {
        try {
          yield await fetchScheduled();
        } catch (e) {
          debugPrint('[ScheduledOrders] Realtime fetch error: $e');
        }
      }
    } catch (e) {
      debugPrint('[ScheduledOrders] Realtime stream error: $e');
    }
  }
}
