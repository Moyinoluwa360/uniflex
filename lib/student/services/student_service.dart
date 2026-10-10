import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/achievement.dart';
import '../../shared/models/advertisement.dart';
import '../../shared/models/gift.dart';

/// Thrown when a student RPC rejects a request for a reason worth showing
/// the student directly (a PIN failure, for instance).
class StudentServiceException implements Exception {
  StudentServiceException(this.message);
  final String message;

  @override
  String toString() => 'StudentServiceException: $message';
}

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

  // ── Referral code (Phase 10) ─────────────────────────────────────────

  /// The referral code Admin allocated to this student, with how many
  /// signups have used it. Null when they have not been given one —
  /// students no longer mint their own at signup.
  Future<Map<String, dynamic>?> getMyReferralCode() async {
    final result = await _client.rpc('my_referral_code');
    if (result == null) return null;
    return Map<String, dynamic>.from(result as Map);
  }

  // ── Advertisements (Phase 10) ────────────────────────────────────────

  /// Live home-page banners, in display order. The read policy already
  /// filters out paused, not-yet-started, and expired ads.
  Future<List<Advertisement>> getLiveAdvertisements() async {
    final rows = await _client
        .from('advertisements')
        .select()
        .order('sort_order');
    return rows
        .map((m) => Advertisement.fromMap(m))
        .where((ad) => ad.isLive)
        .toList();
  }

  // ── Gifts ────────────────────────────────────────────────────────────

  /// Send a food gift to another student identified by matric number.
  ///
  /// [pin] is the sender's transaction PIN. Gifting used to be a complete
  /// bypass of the PIN gate that ordinary orders enforce, so the RPC now
  /// requires it. The result carries an `error` key (INVALID_PIN /
  /// PIN_LOCKED / PIN_NOT_SET) rather than throwing, so the server can
  /// commit the failed-attempt counter behind the lockout.
  Future<Map<String, dynamic>> sendGift({
    required String recipientMatric,
    required String vendorId,
    required List<Map<String, dynamic>> lineItems,
    required double totalAmount,
    required String pin,
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
      'p_pin': pin,
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

  /// Pay this member's share of a group order. [pin] is the transaction PIN
  /// — group checkout was a second PIN-gate bypass alongside gifting.
  /// Throws [StudentServiceException] if the server returns a PIN error.
  Future<String> checkoutGroupOrder({
    required String groupId,
    required List<Map<String, dynamic>> lineItems,
    required double myTotal,
    required String pin,
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
      'p_pin': pin,
    }) as Map<String, dynamic>;

    final error = result['error'] as String?;
    if (error != null) {
      throw StudentServiceException(switch (error) {
        'PIN_LOCKED' =>
          'Too many incorrect PIN attempts. Try again in 15 minutes.',
        'PIN_NOT_SET' => 'Set up your transaction PIN first.',
        _ => 'Incorrect PIN. Please try again.',
      });
    }

    return result['order_id'] as String;
  }

  // ── Group order members stream ───────────────────────────────────────

  Stream<List<Map<String, dynamic>>> streamGroupMembers(String groupId) async* {
    // Immediate fetch.
    final initial = await _client
        .from('group_order_members')
        .select()
        .eq('group_order_id', groupId);
    yield initial.cast<Map<String, dynamic>>();

    // Then Realtime for live updates.
    try {
      final stream = _client
          .from('group_order_members')
          .stream(primaryKey: ['id'])
          .eq('group_order_id', groupId);

      await for (final _ in stream) {
        final rows = await _client
            .from('group_order_members')
            .select()
            .eq('group_order_id', groupId);
        yield rows.cast<Map<String, dynamic>>();
      }
    } catch (_) {
      // Realtime failed; initial data is already showing.
    }
  }
}
