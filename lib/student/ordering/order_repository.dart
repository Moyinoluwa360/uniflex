import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/order.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import '../../shared/services/wallet/wallet_providers.dart';
import 'cart_provider.dart';

// ---------------------------------------------------------------------------
// Read providers
// ---------------------------------------------------------------------------

/// All orders for the signed-in student, newest first. Refresh with
/// `ref.invalidate(studentOrdersProvider)` after placing a new order.
final studentOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return [];

  final data = await client
      .from('orders')
      .select('*, vendors(name)')
      .eq('student_id', user.id)
      .order('created_at', ascending: false);

  return data.map((m) => Order.fromMap(m)).toList();
});

/// A single order by ID, with its line items populated. Used by the
/// tracking screen. Swap for a StreamProvider + Supabase realtime channel
/// in a later phase for live status updates without touching the UI.
final orderByIdProvider =
    FutureProvider.family<Order?, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);

  final data = await client
      .from('orders')
      .select('*, vendors(name), order_items(*)')
      .eq('id', orderId)
      .maybeSingle();

  if (data == null) return null;

  return Order.fromMap(data);
});

// ---------------------------------------------------------------------------
// Write notifier
// ---------------------------------------------------------------------------

/// Result state for order placement. [order] is non-null on success.
/// [budgetWarning] is true when the order succeeded but caused the
/// active saving plan budget to be exceeded for the current period.
class OrderPlacementState {
  const OrderPlacementState({
    this.isLoading = false,
    this.order,
    this.error,
    this.budgetWarning = false,
  });
  final bool isLoading;
  final Order? order;
  final String? error;

  /// True when the order went through but the saving plan budget was
  /// exceeded. The UI shows a soft warning — the order is never blocked.
  final bool budgetWarning;

  bool get isSuccess => order != null;
}

/// Handles placing both food orders and Around requests.
///
/// Both methods call SECURITY DEFINER Postgres RPCs that atomically:
///   1. Row-lock and check the wallet balance (no double-spend)
///   2. Deduct the wallet
///   3. Create the order and related rows
///   4. Record a debit wallet_transaction
///   5. Update the active saving plan's spent counter (lazy period reset)
///
/// After a successful placement the cart is cleared and wallet / order
/// providers are invalidated so UIs refresh automatically.
class OrderNotifier extends Notifier<OrderPlacementState> {
  @override
  OrderPlacementState build() => const OrderPlacementState();

  /// Places a food order for all items currently in the cart.
  ///
  /// [pin] is the student's transaction PIN, verified server-side before
  /// any wallet funds move (see Section 6 — Order confirmation PIN).
  /// [packs] is the pack allocation built at checkout (Section 11) — a
  /// list of `{'items': [{'product_id', 'product_name', 'quantity'}]}`
  /// maps, one per pack; [packFee] is `packs.length * vendor.packPrice`,
  /// already folded into the total the caller computed.
  Future<Order?> placeFoodOrder({
    required Vendor vendor,
    required String deliveryType, // 'pickup' | 'campus_delivery' | 'hostel_delivery'
    required String pin,
    String? deliveryLocation,
    DateTime? scheduledFor,
    bool isBulk = false,
    double bulkDiscountPct = 0,
    List<Map<String, dynamic>> packs = const [],
    double packFee = 0,
  }) async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) return null;

    state = const OrderPlacementState(isLoading: true);

    try {
      final client = ref.read(supabaseClientProvider);
      final deliveryFee = switch (deliveryType) {
        'campus_delivery' => 200.0,
        'hostel_delivery' => 300.0,
        _ => 0.0,
      };
      final total = cart.subtotal + deliveryFee + packFee;

      // Build the JSONB line-items array expected by the RPC.
      final lineItems = cart.items
          .map((item) => {
                'product_id': item.product.id,
                'product_name': item.product.name,
                'quantity': item.quantity,
                'unit_price': item.unitTotal,
                'selected_options':
                    item.selectedOptions.map((o) => o.toJson()).toList(),
              })
          .toList();

      final result = await client.rpc(
        'place_food_order_with_payment',
        params: {
          'p_vendor_id': vendor.id,
          'p_source': vendor.isUniflex ? 'uniflex' : 'partner',
          'p_delivery_type': deliveryType,
          'p_delivery_location': deliveryLocation,
          'p_total_amount': total,
          'p_estimated_time': scheduledFor != null ? 'Scheduled' : '20–30 min',
          'p_line_items': lineItems,
          if (scheduledFor != null)
            'p_scheduled_for': scheduledFor.toUtc().toIso8601String(),
          if (isBulk) 'p_is_bulk': isBulk,
          if (bulkDiscountPct > 0) 'p_bulk_discount_pct': bulkDiscountPct,
          'p_pin': pin,
          'p_pack_fee': packFee,
          'p_packs': packs,
        },
      ) as Map<String, dynamic>;

      final orderId = result['order_id'] as String;
      final planOverBudget = result['plan_over_budget'] as bool? ?? false;

      // Reconstruct a minimal Order for the confirmation screen.
      // The full row will be re-fetched by orderByIdProvider on the
      // tracking screen.
      final order = Order(
        id: orderId,
        studentId: client.auth.currentUser!.id,
        vendorId: vendor.id,
        vendorName: vendor.name,
        source: vendor.isUniflex ? 'uniflex' : 'partner',
        type: 'food',
        status: OrderStatus.placed,
        deliveryType: deliveryType,
        deliveryLocation: deliveryLocation,
        totalAmount: total,
        estimatedTime: scheduledFor != null ? 'Scheduled' : '20–30 min',
        scheduledFor: scheduledFor,
        isBulk: isBulk,
        bulkDiscountPct: bulkDiscountPct,
        packCount: packs.length,
        packFee: packFee,
        createdAt: DateTime.now(),
      );

      ref.read(cartProvider.notifier).clear();
      ref.invalidate(studentOrdersProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);

      state = OrderPlacementState(order: order, budgetWarning: planOverBudget);
      return order;
    } catch (e) {
      state = OrderPlacementState(error: _mapError(e.toString()));
      return null;
    }
  }

  /// Places an Around request (errand, laundry, hostel transfer, etc.).
  /// [categoryKey] and [fee] come from the admin-configurable
  /// `around_categories` table (Section 9) rather than a hardcoded enum.
  Future<Order?> placeAroundRequest({
    required String categoryKey,
    required double fee,
    required String pickupLocation,
    required String dropoffLocation,
    required String itemDescription,
    required String pin,
  }) async {
    state = const OrderPlacementState(isLoading: true);
    try {
      final client = ref.read(supabaseClientProvider);

      final result = await client.rpc(
        'place_around_with_payment',
        params: {
          'p_category': categoryKey,
          'p_pickup_location': pickupLocation,
          'p_dropoff_location': dropoffLocation,
          'p_item_description': itemDescription,
          'p_total_amount': fee,
          'p_pin': pin,
        },
      ) as Map<String, dynamic>;

      final orderId = result['order_id'] as String;
      final planOverBudget = result['plan_over_budget'] as bool? ?? false;

      final order = Order(
        id: orderId,
        studentId: client.auth.currentUser!.id,
        source: 'uniflex',
        type: 'around',
        status: OrderStatus.placed,
        deliveryType: 'delivery',
        totalAmount: fee,
        estimatedTime: '15–25 min',
        createdAt: DateTime.now(),
      );

      ref.invalidate(studentOrdersProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(walletInfoProvider);
      ref.invalidate(walletTransactionsProvider);

      state = OrderPlacementState(order: order, budgetWarning: planOverBudget);
      return order;
    } catch (e) {
      state = OrderPlacementState(error: _mapError(e.toString()));
      return null;
    }
  }

  /// Translates Postgres exception messages into user-facing error strings.
  /// The special value 'insufficient_balance' is detected by the UI to
  /// show a "Fund Wallet" shortcut rather than a generic error.
  String _mapError(String raw) {
    if (raw.contains('INSUFFICIENT_BALANCE')) return 'insufficient_balance';
    if (raw.contains('INVALID_PIN')) return 'invalid_pin';
    if (raw.contains('WALLET_NOT_FOUND')) {
      return 'Wallet not found — please contact support.';
    }
    return raw;
  }

  void reset() => state = const OrderPlacementState();
}

final orderNotifierProvider =
    NotifierProvider<OrderNotifier, OrderPlacementState>(OrderNotifier.new);
