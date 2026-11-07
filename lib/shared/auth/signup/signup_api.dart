import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// A short, friendly failure from the `signup` Edge Function. [code] is the
/// server's machine code (e.g. `EMAIL_TAKEN`); [message] is what we show.
class SignupException implements Exception {
  SignupException(this.code, {this.retryAfter, this.attemptsLeft});

  final String code;

  /// Seconds until another SMS may be requested (TOO_SOON).
  final int? retryAfter;
  final int? attemptsLeft;

  /// Codes that mean "the phone proof is no longer good".
  bool get isProofProblem =>
      code == 'PROOF_EXPIRED' ||
      code == 'PROOF_INVALID' ||
      code == 'PROOF_USED';

  /// Codes that mean "go back and fix step 1".
  bool get isStepOneProblem =>
      code == 'EMAIL_TAKEN' || code == 'EMAIL_STUCK' || code == 'PHONE_TAKEN';

  String get message => switch (code) {
        'EMAIL_TAKEN' =>
          'An account with this email already exists. Try logging in.',
        'EMAIL_STUCK' => 'You already started creating an account with this '
            'email. Log in to continue where you stopped.',
        'PHONE_TAKEN' =>
          'This phone number is already used by another account.',
        'TOO_SOON' => 'Please wait ${retryAfter ?? 60} seconds before asking '
            'for another code.',
        'PHONE_LIMIT' => 'Too many codes were requested for this number today. '
            'Please try again tomorrow.',
        'RATE_LIMITED' =>
          'Too many attempts. Please wait a few minutes and try again.',
        'SEND_FAILED' =>
          "We couldn't reach the SMS service. Please try again in a moment.",
        'CODE_EXPIRED' => 'That code has expired. Request a new one.',
        'TOO_MANY_ATTEMPTS' =>
          'Too many wrong codes. Request a new code to try again.',
        'PROOF_EXPIRED' ||
        'PROOF_INVALID' ||
        'PROOF_USED' =>
          'Your phone verification expired. Please verify your number again.',
        'NICKNAME_TAKEN' => 'That nickname is taken. Try another one.',
        'MATRIC_TAKEN' => 'That matric number is already registered.',
        'REFERRAL_INVALID' => "That referral code isn't valid.",
        'CANNOT_REFER_SELF' => "You can't use your own referral code.",
        'INVALID_INPUT' => 'Please check your details and try again.',
        _ => "We couldn't finish that right now. Please try again.",
      };

  @override
  String toString() => 'SignupException($code)';
}

class SendCodeResult {
  const SendCodeResult({required this.cooldownSeconds});
  final int cooldownSeconds;
}

class VerifyCodeResult {
  const VerifyCodeResult(
      {required this.verified, this.proof, this.attemptsLeft});
  final bool verified;
  final String? proof;
  final int? attemptsLeft;
}

/// The final-step fields, as sent to the server.
class SignupSubmission {
  const SignupSubmission({
    required this.proof,
    required this.email,
    required this.password,
    required this.phone,
    required this.nickname,
    required this.fullName,
    required this.matric,
    required this.school,
    required this.dateOfBirth,
    required this.referral,
    required this.pin,
  });

  final String proof;
  final String email;
  final String password;
  final String phone; // E.164
  final String nickname;
  final String fullName;
  final String? matric;
  final String school;
  final DateTime dateOfBirth;
  final String? referral;
  final String pin;
}

/// Everything the sign-up flow needs from the backend. Real implementation:
/// [SupabaseSignupApi]; tests supply a fake.
abstract class SignupApi {
  /// Checks email + phone are free (server-side) and only THEN sends the SMS.
  Future<SendCodeResult> sendCode({
    required String email,
    required String phone,
    required String deviceId,
  });

  Future<VerifyCodeResult> verifyCode({
    required String phone,
    required String code,
  });

  /// Creates the account. Throws [SignupException] on any refusal.
  Future<void> complete(SignupSubmission s);

  /// Live availability for step 3. `null` = could not tell (offline) — the
  /// server re-checks at submit, so unknown never blocks the person.
  Future<bool?> isNicknameAvailable(String nickname);
  Future<bool?> isMatricAvailable(String matric);
  Future<bool?> isReferralValid(String code);
}

class SupabaseSignupApi implements SignupApi {
  SupabaseSignupApi(this._client);

  final SupabaseClient _client;

  static const _fn = 'signup';

  /// A reply slower than this is treated as a failure instead of leaving the
  /// button spinning forever (the Pack 5 root-cause bug had no timeout).
  static const _timeout = Duration(seconds: 25);

  @override
  Future<SendCodeResult> sendCode({
    required String email,
    required String phone,
    required String deviceId,
  }) async {
    final body = await _call({
      'action': 'send',
      'email': email,
      'phone': phone,
      'device_id': deviceId,
    });
    final cooldown = body['cooldown'];
    return SendCodeResult(cooldownSeconds: cooldown is int ? cooldown : 60);
  }

  @override
  Future<VerifyCodeResult> verifyCode({
    required String phone,
    required String code,
  }) async {
    final body =
        await _call({'action': 'verify', 'phone': phone, 'code': code});
    if (body['verified'] == true && body['proof'] is String) {
      return VerifyCodeResult(verified: true, proof: body['proof'] as String);
    }
    final left = body['attempts_left'];
    return VerifyCodeResult(
      verified: false,
      attemptsLeft: left is int ? left : null,
    );
  }

  @override
  Future<void> complete(SignupSubmission s) async {
    await _call({
      'action': 'complete',
      'proof': s.proof,
      'email': s.email,
      'password': s.password,
      'phone': s.phone,
      'nickname': s.nickname,
      'full_name': s.fullName,
      'matric_number': s.matric,
      'school': s.school,
      'date_of_birth': s.dateOfBirth.toIso8601String().split('T').first,
      'referral_code': s.referral,
      'pin': s.pin,
    });
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    try {
      final response =
          await _client.functions.invoke(_fn, body: payload).timeout(_timeout);
      final data = response.data;
      if (data is Map && data['error'] != null) {
        throw _fromBody(Map<String, dynamic>.from(data));
      }
      if (data is! Map) throw SignupException('SERVER_ERROR');
      return Map<String, dynamic>.from(data);
    } on FunctionException catch (e) {
      final d = e.details;
      if (d is Map && d['error'] != null) {
        throw _fromBody(Map<String, dynamic>.from(d));
      }
      throw SignupException('SERVER_ERROR');
    }
    // TimeoutException / socket errors propagate; AppErrorMapper words them.
  }

  SignupException _fromBody(Map<String, dynamic> m) {
    final retry = m['retry_after'];
    return SignupException(
      m['error'].toString(),
      retryAfter: retry is num ? retry.toInt() : null,
    );
  }

  Future<bool?> _rpcBool(String fn, Map<String, dynamic> params) async {
    try {
      final r = await _client.rpc(fn, params: params).timeout(_timeout);
      return r is bool ? r : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool?> isNicknameAvailable(String nickname) =>
      _rpcBool('is_nickname_available', {'p_nickname': nickname});

  @override
  Future<bool?> isMatricAvailable(String matric) =>
      _rpcBool('is_matric_number_available', {'p_matric_number': matric});

  @override
  Future<bool?> isReferralValid(String code) =>
      _rpcBool('is_referral_code_valid', {'p_code': code});
}

/// `+2348031234567` → `+234 803 ••• 4567` (never shows the whole number on
/// the verify screen).
String maskPhone(String e164) {
  final p = e164.replaceAll(RegExp(r'\s'), '');
  if (p.startsWith('+234') && p.length == 14) {
    return '+234 ${p.substring(4, 7)} ••• ${p.substring(10)}';
  }
  if (p.length <= 6) return p;
  return '${p.substring(0, 4)} ••• ${p.substring(p.length - 4)}';
}
