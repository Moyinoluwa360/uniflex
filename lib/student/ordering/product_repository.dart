import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/product.dart';
import '../../shared/models/vendor.dart';
import '../../shared/services/supabase/supabase_providers.dart';

/// All active vendors, ordered with featured (Uniflex) first then by name.
final vendorsProvider = FutureProvider<List<Vendor>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('vendors')
      .select()
      .eq('is_active', true)
      .order('is_featured', ascending: false)
      .order('name');
  return (data as List)
      .map((m) => Vendor.fromMap(m as Map<String, dynamic>))
      .toList();
});

/// Products for [vendorId] — each one independently orderable (post-
/// testing fixes, Section 11: no more per-product options merge here,
/// since the catalog no longer drives a protein/extras combo-builder).
final vendorProductsProvider =
    FutureProvider.family<List<Product>, String>((ref, vendorId) async {
  final client = ref.watch(supabaseClientProvider);

  final productsData = await client
      .from('products')
      .select()
      .eq('vendor_id', vendorId)
      .eq('is_available', true)
      .order('category')
      .order('name');

  return (productsData as List)
      .map((m) => Product.fromMap(m as Map<String, dynamic>))
      .toList();
});
