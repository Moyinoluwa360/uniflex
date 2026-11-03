import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/errand_category.dart';
import '../../shared/services/supabase/supabase_providers.dart';

/// Active Errand categories, admin-configurable. Read dynamically instead
/// of the old hardcoded enum, so adding/editing/removing a category from
/// the admin Manage hub reflects here without an app update.
final activeErrandCategoriesProvider =
    FutureProvider<List<ErrandCategoryData>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('errand_categories')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return data.map((m) => ErrandCategoryData.fromMap(m)).toList();
});

/// Anonymous rider-availability signal (Section 10) — true when at least
/// one rider is online, with no name or per-rider status ever exposed.
final ridersAvailableNearbyProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('any_riders_available');
  return result as bool;
});
