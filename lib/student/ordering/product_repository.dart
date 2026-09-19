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

/// Products for [vendorId], grouped — each product's options are
/// fetched in a second query and merged in before returning.
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

  final products = (productsData as List)
      .map((m) => Product.fromMap(m as Map<String, dynamic>))
      .toList();

  if (products.isEmpty) return products;

  final productIds = products.map((p) => p.id).toList();
  final optionsData = await client
      .from('product_options')
      .select()
      .inFilter('product_id', productIds);

  // Group options by product_id
  final optionsByProduct = <String, List<ProductOption>>{};
  for (final m in optionsData as List) {
    final map = m as Map<String, dynamic>;
    final opt = ProductOption.fromMap(map);
    optionsByProduct.putIfAbsent(map['product_id'] as String, () => []).add(opt);
  }

  return products
      .map((p) => p.copyWith(options: optionsByProduct[p.id] ?? []))
      .toList();
});
