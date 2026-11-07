import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/services/supabase/supabase_providers.dart';
import 'gift_models.dart';

/// Looks a gift recipient up by registration email.
abstract class GiftRepository {
  Future<GiftLookupResult> lookup(String email);
}

class SupabaseGiftRepository implements GiftRepository {
  const SupabaseGiftRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<GiftLookupResult> lookup(String email) async {
    final raw =
        await _client.rpc('lookup_gift_recipient', params: {'p_email': email});
    return GiftLookupResult.fromMap(
        email, Map<String, dynamic>.from(raw as Map));
  }
}

final giftRepositoryProvider = Provider<GiftRepository>((ref) {
  return SupabaseGiftRepository(ref.watch(supabaseClientProvider));
});

/// Gifts the signed-in student RECEIVES, live. Reads only `gift_deliveries`
/// (the recipient-only mirror) — never the sender's order.
final receivedGiftsProvider = StreamProvider<List<GiftDelivery>>((ref) {
  final client = ref.watch(supabaseClientProvider);
  final user = client.auth.currentUser;
  if (user == null) return Stream.value(const []);
  return _streamGifts(client, user.id);
});

/// One received gift by its order id (what a notification carries).
final receivedGiftByGroupProvider =
    Provider.family<AsyncValue<GiftDelivery?>, String>((ref, groupId) {
  return ref.watch(receivedGiftsProvider).whenData((list) {
    for (final g in list) {
      if (g.groupId == groupId) return g;
    }
    return null;
  });
});

Stream<List<GiftDelivery>> _streamGifts(
    SupabaseClient client, String userId) async* {
  Future<List<GiftDelivery>> fetch() async {
    final rows = await client
        .from('gift_deliveries')
        .select()
        .eq('recipient_id', userId)
        .order('created_at', ascending: false);
    return rows.map((m) => GiftDelivery.fromMap(m)).toList();
  }

  yield await fetch();
  try {
    final stream = client
        .from('gift_deliveries')
        .stream(primaryKey: ['group_id']).eq('recipient_id', userId);
    await for (final _ in stream) {
      yield await fetch();
    }
  } catch (_) {
    // Realtime failed; the first fetch is already showing.
  }
}
