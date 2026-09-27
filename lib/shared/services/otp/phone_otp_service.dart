import 'package:supabase_flutter/supabase_flutter.dart';

/// Result of requesting an OTP send.
class OtpSendResult {
  const OtpSendResult({required this.pinId});

  /// Termii's reference for this OTP attempt — must be sent back with the
  /// code on verify.
  final String pinId;
}

/// Thrown for any OTP failure (bad request, provider error, rate limit) so
/// callers can show one consistent message.
class OtpException implements Exception {
  OtpException(this.message);
  final String message;

  @override
  String toString() => 'OtpException: $message';
}

/// Phone OTP verification, proxied through the `phone-otp` Edge Function.
///
/// Supabase's own phone auth is deliberately not used — Termii is the OTP
/// provider the spec calls for. The client used to talk to Termii directly,
/// but that required shipping TERMII_API_KEY inside the app bundle (where
/// it is extractable and billable), and it left the client deciding whether
/// verification succeeded. Both now happen server-side: the Edge Function
/// holds the key, and it is the only thing that writes
/// `profiles.phone_verified_at`.
class PhoneOtpService {
  const PhoneOtpService(this._client);

  final SupabaseClient _client;

  static const _functionName = 'phone-otp';

  /// Sends a numeric OTP to [phoneNumber] (E.164, e.g. `+2348012345678`).
  /// Returns the `pinId` needed to verify the code the user enters.
  Future<OtpSendResult> sendOtp(String phoneNumber) async {
    final body = await _invoke({'action': 'send', 'phone': phoneNumber});
    final pinId = body['pin_id'] as String?;
    if (pinId == null) {
      throw OtpException('Could not send verification code.');
    }
    return OtpSendResult(pinId: pinId);
  }

  /// Verifies [pin] against the OTP attempt identified by [pinId]. On
  /// success the server has already recorded [phoneNumber] and the
  /// verified-at timestamp on the caller's profile.
  Future<bool> verifyOtp({
    required String pinId,
    required String pin,
    required String phoneNumber,
  }) async {
    final body = await _invoke({
      'action': 'verify',
      'pin_id': pinId,
      'pin': pin,
      'phone': phoneNumber,
    });
    return body['verified'] == true;
  }

  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> payload) async {
    try {
      final response = await _client.functions.invoke(
        _functionName,
        body: payload,
      );
      final data = response.data;
      if (data is! Map) {
        throw OtpException('Unexpected response from verification service.');
      }
      final map = Map<String, dynamic>.from(data);
      if (map['error'] != null) {
        throw OtpException(map['error'].toString());
      }
      return map;
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map && details['error'] != null
          ? details['error'].toString()
          : 'Could not reach the verification service.';
      throw OtpException(message);
    }
  }
}
