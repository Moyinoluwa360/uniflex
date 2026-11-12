import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/profile.dart';

/// Thrown when a uniqueness constraint (nickname, matric number) or a
/// referral-code lookup fails, with a message safe to show directly to
/// the user.
class ProfileException implements Exception {
  ProfileException(this.message);
  final String message;

  @override
  String toString() => 'ProfileException: $message';
}

/// Wraps `profiles`/`wallets` access for onboarding. Uniqueness checks and
/// the Step Two write go through the RPC functions in
/// `supabase/schema.sql` rather than raw table access — see that file for
/// why (atomicity, and keeping the profiles table itself off directly
/// insertable/selectable by other users).
class ProfileService {
  ProfileService(this._client);

  final SupabaseClient _client;

  // Pack 5: createStubProfile() was removed. No profile row is written
  // before the account is complete; the `signup` Edge Function creates the
  // profile, wallet, PIN and referral together at the last step. Legacy
  // stubs created by the old flow are still read via [fetchProfile] and
  // finished via [completeStudentOnboarding].

  Future<Profile?> fetchProfile(String userId) async {
    final row =
        await _client.from('profiles').select().eq('id', userId).maybeSingle();
    if (row == null) return null;
    return Profile.fromMap(row);
  }

  Future<bool> isNicknameAvailable(String nickname) async {
    final result = await _client.rpc(
      'is_nickname_available',
      params: {'p_nickname': nickname},
    );
    return result as bool;
  }

  Future<bool> isMatricNumberAvailable(String matricNumber) async {
    final result = await _client.rpc(
      'is_matric_number_available',
      params: {'p_matric_number': matricNumber},
    );
    return result as bool;
  }

  Future<bool> isReferralCodeValid(String code) async {
    final result = await _client.rpc(
      'is_referral_code_valid',
      params: {'p_code': code},
    );
    return result as bool;
  }

  /// Step Two submit — creates the profile, wallet, referral code, and
  /// (if a valid code was entered) the referral relationship, all in one
  /// server-side transaction. See complete_student_onboarding() in
  /// supabase/schema.sql.
  Future<Profile> completeStudentOnboarding({
    required String nickname,
    required String fullName,
    String? matricNumber,
    required String school,
    required DateTime dateOfBirth,
    String? referralCodeUsed,
  }) async {
    try {
      final row = await _client.rpc(
        'complete_student_onboarding',
        params: {
          'p_nickname': nickname,
          'p_full_name': fullName,
          'p_matric_number': matricNumber,
          'p_school': school,
          'p_date_of_birth': dateOfBirth.toIso8601String().split('T').first,
          'p_referral_code_used': referralCodeUsed,
        },
      );
      return Profile.fromMap(row as Map<String, dynamic>);
    } on PostgrestException catch (e) {
      throw ProfileException(e.message);
    }
  }

  // ── Transaction PIN (post-testing fixes, Section 6) ───────────────────

  /// True once this student has set a 4-digit transaction PIN. Existing
  /// accounts created before this feature return false until they set one.
  Future<bool> hasTransactionPin() async {
    final result = await _client.rpc('has_transaction_pin');
    return result as bool;
  }

  /// Sets the signed-in student's transaction PIN. [pin] must be exactly 4
  /// digits — validated again server-side.
  ///
  /// [currentPin] is required when a PIN already exists: changing one used
  /// to need no proof of the old one, so a stolen session could silently
  /// replace the PIN and then spend the wallet.
  Future<void> setTransactionPin(String pin, {String? currentPin}) async {
    dynamic result;
    try {
      result = await _client.rpc('set_transaction_pin', params: {
        'p_pin': pin,
        if (currentPin != null) 'p_current_pin': currentPin,
      });
    } on PostgrestException catch (e) {
      if (e.message.contains('INVALID_CURRENT_PIN')) {
        throw ProfileException('That is not your current PIN.');
      }
      if (e.message.contains('crypt')) {
        throw ProfileException(
            'Server configuration error. Please contact support.');
      }
      throw ProfileException(e.message);
    }
    // Pack 2: a wrong / locked current PIN is RETURNED (so the server's
    // failed-attempt counter is kept), not raised.
    final error = result is Map ? result['error'] : null;
    if (error == 'INVALID_CURRENT_PIN') {
      throw ProfileException('That is not your current PIN.');
    }
    if (error == 'PIN_LOCKED') {
      throw ProfileException(
          'Too many wrong attempts — PIN is locked for 15 minutes.');
    }
    if (error is String && error.isNotEmpty) {
      throw ProfileException('Could not change your PIN. Please try again.');
    }
  }
}
