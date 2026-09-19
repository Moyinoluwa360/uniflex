import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/around_category.dart';
import '../../shared/services/supabase/supabase_providers.dart';

/// Active Around categories, admin-configurable (post-testing fixes,
/// Section 9). Read dynamically instead of the old hardcoded enum, so
/// adding/editing/removing a category from the admin Manage hub reflects
/// here without an app update.
final activeAroundCategoriesProvider =
    FutureProvider<List<AroundCategoryData>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from('around_categories')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return data.map((m) => AroundCategoryData.fromMap(m)).toList();
});

/// Anonymous rider-availability signal (Section 10) — true when at least
/// one rider is online, with no name or per-rider status ever exposed.
final ridersAvailableNearbyProvider = FutureProvider<bool>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final result = await client.rpc('any_riders_available');
  return result as bool;
});
