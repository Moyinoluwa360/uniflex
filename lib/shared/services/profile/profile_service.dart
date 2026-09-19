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

  /// Creates the bare profiles row right after Step One's Supabase Auth
  /// user is created, so phone/phone_verified_at have somewhere to land
  /// before Step Two (Complete Your Profile) runs. Role defaults to
  /// 'student' and onboarding_complete defaults to false at the database
  /// level (see supabase/schema.sql).
  Future<void> createStubProfile({
    required String userId,
    required String email,
  }) async {
    await _client.from('profiles').insert({'id': userId, 'email': email});
  }

  /// Records that Termii verified this phone number, ahead of Step Two.
  Future<void> markPhoneVerified({
    required String userId,
    required String phone,
  }) async {
    await _client
        .from('profiles')
        .update({
          'phone': phone,
          'phone_verified_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', userId);
  }

  Future<Profile?> fetchProfile(String userId) async {
    final row = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
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
    required String matricNumber,
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
}
