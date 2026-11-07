import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/uuid_v4.dart';

/// How long a half-finished sign-up is remembered on the phone.
const Duration kDraftLifetime = Duration(hours: 24);

/// The server's phone-verification proof lasts 30 minutes; the app treats it
/// as expired a minute early so a submit never races the server clock.
const Duration kProofLifetime = Duration(minutes: 29);

/// Everything a half-finished sign-up remembers — EXCEPT the password
/// (secure storage only, see [SignupDraftStore]) and the transaction PIN
/// (never stored anywhere).
class SignupDraft {
  const SignupDraft({
    this.step = 1,
    this.email = '',
    this.phoneInput = '',
    this.nickname = '',
    this.fullName = '',
    this.matric = '',
    this.school = "Redeemer's University",
    this.dateOfBirth,
    this.referral = '',
    this.proof,
    this.proofAt,
    this.codeSentAt,
    this.savedAt,
  });

  /// 1 = your details, 2 = verify phone, 3 = final details.
  final int step;
  final String email;

  /// The phone exactly as typed (e.g. `0803…`); normalised when used.
  final String phoneInput;
  final String nickname;
  final String fullName;
  final String matric;
  final String school;
  final DateTime? dateOfBirth;
  final String referral;

  /// Server-issued proof that [phoneInput] was verified. Single use.
  final String? proof;
  final DateTime? proofAt;

  /// When the last SMS was requested (drives the 60 s resend countdown).
  final DateTime? codeSentAt;

  /// Last time anything was saved — the 24 h expiry counts from here.
  final DateTime? savedAt;

  bool get isEmpty =>
      email.isEmpty &&
      phoneInput.isEmpty &&
      nickname.isEmpty &&
      fullName.isEmpty &&
      matric.isEmpty &&
      referral.isEmpty &&
      dateOfBirth == null &&
      step == 1;

  bool proofIsFresh(DateTime now) =>
      proof != null &&
      proofAt != null &&
      now.difference(proofAt!) < kProofLifetime;

  SignupDraft copyWith({
    int? step,
    String? email,
    String? phoneInput,
    String? nickname,
    String? fullName,
    String? matric,
    String? school,
    DateTime? dateOfBirth,
    String? referral,
    String? proof,
    DateTime? proofAt,
    DateTime? codeSentAt,
    DateTime? savedAt,
    bool clearProof = false,
    bool clearCodeSentAt = false,
    bool clearDateOfBirth = false,
  }) {
    return SignupDraft(
      step: step ?? this.step,
      email: email ?? this.email,
      phoneInput: phoneInput ?? this.phoneInput,
      nickname: nickname ?? this.nickname,
      fullName: fullName ?? this.fullName,
      matric: matric ?? this.matric,
      school: school ?? this.school,
      dateOfBirth: clearDateOfBirth ? null : (dateOfBirth ?? this.dateOfBirth),
      referral: referral ?? this.referral,
      proof: clearProof ? null : (proof ?? this.proof),
      proofAt: clearProof ? null : (proofAt ?? this.proofAt),
      codeSentAt: clearCodeSentAt ? null : (codeSentAt ?? this.codeSentAt),
      savedAt: savedAt ?? this.savedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'step': step,
        'email': email,
        'phone': phoneInput,
        'nickname': nickname,
        'full_name': fullName,
        'matric': matric,
        'school': school,
        'dob': dateOfBirth?.toIso8601String(),
        'referral': referral,
        'proof': proof,
        'proof_at': proofAt?.toIso8601String(),
        'code_sent_at': codeSentAt?.toIso8601String(),
        'saved_at': savedAt?.toIso8601String(),
        // Deliberately no 'password' and no 'pin' key — ever.
      };

  factory SignupDraft.fromJson(Map<String, dynamic> j) {
    DateTime? d(String k) =>
        j[k] is String ? DateTime.tryParse(j[k] as String) : null;
    final step = j['step'];
    return SignupDraft(
      step: step is int && step >= 1 && step <= 3 ? step : 1,
      email: (j['email'] as String?) ?? '',
      phoneInput: (j['phone'] as String?) ?? '',
      nickname: (j['nickname'] as String?) ?? '',
      fullName: (j['full_name'] as String?) ?? '',
      matric: (j['matric'] as String?) ?? '',
      school: (j['school'] as String?) ?? "Redeemer's University",
      dateOfBirth: d('dob'),
      referral: (j['referral'] as String?) ?? '',
      proof: j['proof'] as String?,
      proofAt: d('proof_at'),
      codeSentAt: d('code_sent_at'),
      savedAt: d('saved_at'),
    );
  }
}

/// A tiny key/value store for secrets. The real one is the OS keystore /
/// keychain; tests use [MemorySecretStore].
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore(
      [this._storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      )]);
  final FlutterSecureStorage _storage;

  // The keystore can fail (corrupted Android keystore, locked keychain). A
  // failure must never break sign-up: a missing password just means the
  // person re-types it on step 1, so errors are swallowed here.
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
    } catch (_) {}
  }

  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> data = {};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

/// Saves the half-finished sign-up on the phone.
///  * the draft (step, fields, proof) → shared preferences, as JSON
///  * the password → [SecretStore] (keystore/keychain) ONLY
///  * the transaction PIN → never stored
///  * expires [kDraftLifetime] after the last save; cleared on success
class SignupDraftStore {
  SignupDraftStore(
    this._prefs,
    this._secrets, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final SecretStore _secrets;
  final DateTime Function() _now;

  static const draftKey = 'signup_draft_v1';
  static const passwordKey = 'signup_draft_password_v1';
  static const deviceKey = 'signup_device_id_v1';

  /// The saved draft, or null if there is none / it expired / it is
  /// unreadable (an expired or corrupt draft is also wiped).
  Future<SignupDraft?> load() async {
    final raw = _prefs.getString(draftKey);
    if (raw == null) return null;
    try {
      final draft = SignupDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
      final saved = draft.savedAt;
      if (saved == null || _now().difference(saved) > kDraftLifetime) {
        await clear();
        return null;
      }
      return draft;
    } catch (_) {
      await clear();
      return null;
    }
  }

  /// Saves [draft] (stamping `savedAt`). [password] is written to secure
  /// storage when given; pass null to leave the stored one untouched.
  Future<SignupDraft> save(SignupDraft draft, {String? password}) async {
    final stamped = draft.copyWith(savedAt: _now());
    await _prefs.setString(draftKey, jsonEncode(stamped.toJson()));
    if (password != null) {
      await _secrets.write(passwordKey, password);
    }
    return stamped;
  }

  Future<String?> readPassword() => _secrets.read(passwordKey);

  /// Forgets the whole draft and the password (success, "Start over",
  /// expiry). The device id is kept — it identifies the phone, not a person.
  Future<void> clear() async {
    await _prefs.remove(draftKey);
    await _secrets.delete(passwordKey);
  }

  /// A random id for this install, sent with OTP requests so the server can
  /// rate limit per device as well as per IP / phone.
  Future<String> deviceId() async {
    var id = _prefs.getString(deviceKey);
    if (id == null || id.isEmpty) {
      id = newUuidV4();
      await _prefs.setString(deviceKey, id);
    }
    return id;
  }
}
