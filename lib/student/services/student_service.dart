import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/achievement.dart';
import '../../shared/models/gift.dart';

/// Thin wrapper around Phase 6 Supabase RPCs used exclusively by the
/// student experience. Rider/Admin features live in their own services.
class StudentService {
  const StudentService(this._client);

  final SupabaseClient _client;

  // ── Stats ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStudentStats() async {
    final result = await _client.rpc('get_student_stats');
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ── Referral ─────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getReferralLeaderboard() async {
    final result = await _client.rpc('get_referral_leaderboard');
    if (result == null) return [];
    return List<Map<String, dynamic>>.from(result as List);
  }

  // ── Achievements ─────────────────────────────────────────────────────

  Future<List<Achievement>> getUserAchievements() async {
    final result = await _client.rpc('get_user_achievements');
    if (result == null) return [];
    return (result as List)
        .map((m) => Achievement.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  // ── Gifts ────────────────────────────────────────────────────────────

  /// Send a food gift to another student identified by matric number.
  Future<Map<String, dynamic>> sendGift({
    required String recipientMatric,
    required String vendorId,
    required List<Map<String, dynamic>> lineItems,
    required double totalAmount,
    String? message,
    String deliveryType = 'pickup',
    String? deliveryLocation,
  }) async {
    final result = await _client.rpc('send_gift', params: {
      'p_recipient_matric': recipientMatric,
      'p_vendor_id': vendorId,
      'p_line_items': lineItems,
      'p_total_amount': totalAmount,
      'p_message': message,
      'p_delivery_type': deliveryType,
      'p_delivery_location': deliveryLocation,
    });
    return result as Map<String, dynamic>;
  }

  Future<List<Gift>> getGifts() async {
    final result = await _client.rpc('get_gifts');
    if (result == null) return [];
    return (result as List)
        .map((m) => Gift.fromMap(m as Map<String, dynamic>))
        .toList();
  }

  // ── Group Orders ─────────────────────────────────────────────────────

  Future<String> createGroupOrder({
    required String vendorId,
    double bulkDiscount = 0,
  }) async {
    final result = await _client.rpc('create_group_order', params: {
      'p_vendor_id': vendorId,
      'p_bulk_discount': bulkDiscount,
    });
    return result as String;
  }

  Future<void> joinGroupOrder(String groupId) async {
    await _client.rpc('join_group_order', params: {'p_group_id': groupId});
  }

  Future<String> checkoutGroupOrder({
    required String groupId,
    required List<Map<String, dynamic>> lineItems,
    required double myTotal,
    String deliveryType = 'pickup',
    String? deliveryLocation,
  }) async {
    final result =
        await _client.rpc('checkout_group_order', params: {
      'p_group_id': groupId,
      'p_line_items': lineItems,
      'p_my_total': myTotal,
      'p_delivery_type': deliveryType,
      'p_delivery_location': deliveryLocation,
    }) as Map<String, dynamic>;
    return result['order_id'] as String;
  }

  // ── Group order members stream ───────────────────────────────────────

  Stream<List<Map<String, dynamic>>> streamGroupMembers(String groupId) {
    return _client
        .from('group_order_members')
        .stream(primaryKey: ['id'])
        .eq('group_order_id', groupId)
        .map((rows) => rows.cast<Map<String, dynamic>>());
  }
}
