import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/supabase/supabase_providers.dart';
import 'order_breakdown_models.dart';

/// Loads an order's contents through the one server function every role
/// uses. [orderId] is a delivery-group id or a standalone (pickup) order id.
///
/// The REAL error is logged in debug builds: the friendly "Could not load
/// item details" message used to hide that the server function was broken.
final orderBreakdownProvider = FutureProvider.autoDispose
    .family<OrderBreakdownData, String>((ref, orderId) async {
  final client = ref.watch(supabaseClientProvider);
  try {
    final raw =
        await client.rpc('get_order_breakdown', params: {'p_id': orderId});
    return OrderBreakdownData.fromJson(Map<String, dynamic>.from(raw as Map));
  } catch (e, st) {
    debugPrint('[OrderBreakdown] load failed for $orderId: $e\n$st');
    rethrow;
  }
});
