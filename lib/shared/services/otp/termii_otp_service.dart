import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../config/env_config.dart';

/// Result of requesting an OTP send from Termii.
class OtpSendResult {
  const OtpSendResult({required this.pinId});

  /// Termii's reference for this OTP attempt — must be sent back with the
  /// code on verify.
  final String pinId;
}

/// Thrown for any Termii API failure (bad request, non-2xx, or a response
/// shape this client doesn't recognise) so callers can show one
/// consistent error message.
class TermiiException implements Exception {
  TermiiException(this.message);
  final String message;

  @override
  String toString() => 'TermiiException: $message';
}

/// Phone OTP verification via Termii's REST API. Supabase's own phone
/// auth is deliberately not used here — Termii is the OTP provider the
/// spec calls for, so this app sends/verifies OTPs itself and only
/// records the resulting phone number + verified-at timestamp on the
/// `profiles` row once Termii confirms the code.
///
/// https://developers.termii.com/otp
class TermiiOtpService {
  TermiiOtpService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://api.ng.termii.com/api';

  /// Sends a numeric OTP to [phoneNumber] (E.164, e.g. `+2348012345678`).
  /// Returns the `pinId` needed to verify the code the user enters.
  Future<OtpSendResult> sendOtp(String phoneNumber) async {
    final apiKey = EnvConfig.termiiApiKey;
    if (apiKey.isEmpty) {
      throw TermiiException(
        'TERMII_API_KEY is not set — copy .env.example to .env and fill it in.',
      );
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/sms/otp/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'api_key': apiKey,
        'message_type': 'NUMERIC',
        'to': phoneNumber,
        // Termii's shared generic sender ID — swap for a registered
        // sender ID once one exists for the project.
        'from': 'Termii',
        'channel': 'generic',
        'pin_attempts': 3,
        'pin_time_to_live': 10,
        'pin_length': 6,
        'pin_placeholder': '< 1234 >',
        'message_text':
            'Your Uniflex verification code is < 1234 >. It expires in 10 minutes.',
      }),
    );

    final body = _decode(response);
    final pinId = body['pinId'] as String?;
    if (response.statusCode != 200 || pinId == null) {
      throw TermiiException(
        (body['message'] as String?) ?? 'Could not send verification code.',
      );
    }

    return OtpSendResult(pinId: pinId);
  }

  /// Verifies [pin] against the OTP attempt identified by [pinId].
  /// Returns true only when Termii reports the code as verified.
  Future<bool> verifyOtp({required String pinId, required String pin}) async {
    final apiKey = EnvConfig.termiiApiKey;
    if (apiKey.isEmpty) {
      throw TermiiException(
        'TERMII_API_KEY is not set — copy .env.example to .env and fill it in.',
      );
    }

    final response = await _client.post(
      Uri.parse('$_baseUrl/sms/otp/verify'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'api_key': apiKey, 'pin_id': pinId, 'pin': pin}),
    );

    final body = _decode(response);
    if (response.statusCode != 200) {
      throw TermiiException(
        (body['message'] as String?) ?? 'Could not verify code.',
      );
    }

    final verified = body['verified'];
    return verified == true || verified == 'True' || verified == 'true';
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.body.isEmpty) return const {};
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } on FormatException {
      return const {};
    }
  }

  void dispose() => _client.close();
}
