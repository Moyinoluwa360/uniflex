import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../utils/app_error_mapper.dart';
import '../validators.dart';
import 'signup_api.dart';
import 'signup_draft.dart';

enum SignupOutcome { created, createdButSignInFailed, failed }

/// The brain of the 3-step sign-up (Pack 5). No widgets in here, so every
/// transition is unit-tested:
///
///   step 1  details ── send OK ──▶ step 2  verify ── code OK ──▶ step 3  final
///      ▲                              │                               │
///      └────── change number ─────────┘◀── proof expired / rejected ──┘
///
/// RULES THE FLOW IS BUILT AROUND
///  * Nothing is created in the backend until [submitFinal] succeeds. Steps
///    1–2 only send/check an SMS code and hold a server-issued *proof*.
///  * Step 1 → 2 happens ONLY when the server confirms the SMS was sent (or
///    one was sent a moment ago). Any failure leaves the person on step 1
///    with a short message. Navigation depends on the send result, never on
///    some other state changing underneath.
///  * Everything is saved to the phone as it happens ([SignupDraftStore]) so
///    leaving and coming back resumes the same step.
class SignupFlowController extends ChangeNotifier {
  SignupFlowController({
    required this.store,
    required this.api,
    required this.signIn,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SignupDraftStore store;
  final SignupApi api;

  /// Signs in with the new account's email + password (AuthService).
  final Future<void> Function(String email, String password) signIn;
  final DateTime Function() _now;

  /// Server cooldown between SMS to one number.
  static const int resendCooldownSeconds = 60;

  SignupDraft draft = const SignupDraft();

  /// Held in memory while the screen is open; persisted only in secure storage.
  String? password;

  bool loaded = false;
  bool busy = false;

  /// Banner text for the current step (null = none).
  String? error;

  int get step => draft.step;
  String get phoneE164 => AuthValidators.toE164(draft.phoneInput);

  /// Seconds left before "Resend" is allowed (0 = allowed now).
  int get cooldownRemaining {
    final sent = draft.codeSentAt;
    if (sent == null) return 0;
    final left =
        resendCooldownSeconds * 1000 - _now().difference(sent).inMilliseconds;
    return left <= 0 ? 0 : (left / 1000).ceil();
  }

  /// Is there anything worth offering "Start over" for?
  bool get hasProgress => !draft.isEmpty || password != null;

  void _set({bool? busy, String? error, bool clearError = false}) {
    if (busy != null) this.busy = busy;
    if (clearError) {
      this.error = null;
    } else if (error != null) {
      this.error = error;
    }
    notifyListeners();
  }

  // ── resume ─────────────────────────────────────────────────────────────
  Future<void> load() async {
    final saved = await store.load();
    password = await store.readPassword();
    draft = saved ?? const SignupDraft();

    // The password lives in the keystore; if it vanished (reinstall, wiped
    // keychain) the person simply re-types it on step 1.
    if (draft.step >= 2 &&
        (password == null || draft.phoneInput.isEmpty || draft.email.isEmpty)) {
      draft = draft.copyWith(step: 1, clearProof: true, clearCodeSentAt: true);
    }
    if (draft.step == 3 && !draft.proofIsFresh(_now())) {
      draft = draft.copyWith(step: 2, clearProof: true);
      error = SignupException('PROOF_EXPIRED').message;
    }
    loaded = true;
    notifyListeners();
  }

  // ── step 1 → 2 ─────────────────────────────────────────────────────────
  /// Returns true only when the person should now be shown step 2.
  Future<bool> submitDetails({
    required String email,
    required String phoneInput,
    required String password,
  }) async {
    if (busy) return false;
    _set(busy: true, clearError: true);

    var next = draft.copyWith(
      email: email.trim(),
      phoneInput: phoneInput.trim(),
      // A new SMS is about to be sent → any earlier verification is discarded.
      clearProof: true,
    );
    final e164 = AuthValidators.toE164(phoneInput);

    try {
      final deviceId = await store.deviceId();
      await api.sendCode(
        email: next.email.toLowerCase(),
        phone: e164,
        deviceId: deviceId,
      );
      this.password = password;
      draft = await store.save(
        next.copyWith(step: 2, codeSentAt: _now()),
        password: password,
      );
      _set(busy: false);
      return true;
    } on SignupException catch (e) {
      if (e.code == 'TOO_SOON') {
        // A code for this number went out a moment ago (double tap, or the
        // reply got lost) — it's on its way, so go on to step 2.
        final wait = (e.retryAfter ?? resendCooldownSeconds)
            .clamp(1, resendCooldownSeconds);
        this.password = password;
        draft = await store.save(
          next.copyWith(
            step: 2,
            codeSentAt: _now()
                .subtract(Duration(seconds: resendCooldownSeconds - wait)),
          ),
          password: password,
        );
        _set(busy: false);
        return true;
      }
      this.password = password;
      draft = await store.save(next, password: password);
      _set(busy: false, error: e.message);
      return false;
    } catch (e) {
      this.password = password;
      draft = await store.save(next, password: password);
      _set(busy: false, error: AppErrorMapper.map(e));
      return false;
    }
  }

  // ── step 2 ─────────────────────────────────────────────────────────────
  Future<bool> resend() async {
    if (busy || cooldownRemaining > 0 || draft.step != 2) return false;
    _set(busy: true, clearError: true);
    try {
      await api.sendCode(
        email: draft.email.toLowerCase(),
        phone: phoneE164,
        deviceId: await store.deviceId(),
      );
      draft = await store.save(draft.copyWith(codeSentAt: _now()));
      _set(busy: false);
      return true;
    } on SignupException catch (e) {
      if (e.code == 'TOO_SOON') {
        final wait = (e.retryAfter ?? resendCooldownSeconds)
            .clamp(1, resendCooldownSeconds);
        draft = await store.save(draft.copyWith(
          codeSentAt:
              _now().subtract(Duration(seconds: resendCooldownSeconds - wait)),
        ));
        _set(busy: false, error: e.message);
      } else if (e.isStepOneProblem) {
        // e.g. someone registered this email/number while we waited.
        draft = await store.save(
            draft.copyWith(step: 1, clearProof: true, clearCodeSentAt: true));
        _set(busy: false, error: e.message);
      } else {
        _set(busy: false, error: e.message);
      }
      return false;
    } catch (e) {
      _set(busy: false, error: AppErrorMapper.map(e));
      return false;
    }
  }

  /// Wrong number? Back to step 1 with every field still filled. The old
  /// verification is thrown away; the new number must pass the availability
  /// check and gets a fresh code.
  Future<void> changeNumber() async {
    draft = await store
        .save(draft.copyWith(step: 1, clearProof: true, clearCodeSentAt: true));
    _set(busy: false, clearError: true);
  }

  Future<bool> verify(String code) async {
    if (busy) return false;
    _set(busy: true, clearError: true);
    try {
      final r = await api.verifyCode(phone: phoneE164, code: code.trim());
      if (r.verified && r.proof != null) {
        draft = await store.save(draft.copyWith(
          step: 3,
          proof: r.proof,
          proofAt: _now(),
          clearCodeSentAt: true,
        ));
        _set(busy: false);
        return true;
      }
      final left = r.attemptsLeft;
      _set(
        busy: false,
        error: left == null
            ? 'That code is incorrect. Try again.'
            : left <= 0
                ? SignupException('TOO_MANY_ATTEMPTS').message
                : 'That code is incorrect. $left ${left == 1 ? 'try' : 'tries'} left.',
      );
      return false;
    } on SignupException catch (e) {
      _set(busy: false, error: e.message);
      return false;
    } catch (e) {
      _set(busy: false, error: AppErrorMapper.map(e));
      return false;
    }
  }

  // ── step 3 ─────────────────────────────────────────────────────────────
  /// Remembers the step-3 fields (never the PIN).
  Future<void> saveFinalFields({
    required String nickname,
    required String fullName,
    required String matric,
    required String school,
    required String referral,
    DateTime? dateOfBirth,
  }) async {
    draft = await store.save(draft.copyWith(
      nickname: nickname,
      fullName: fullName,
      matric: matric,
      school: school,
      referral: referral,
      dateOfBirth: dateOfBirth,
    ));
  }

  /// The proof ran out while the person sat on step 3 → back to step 2 with
  /// every other detail kept.
  Future<void> expireProof() async {
    if (draft.step != 3) return;
    draft = await store.save(draft.copyWith(step: 2, clearProof: true));
    _set(busy: false, error: SignupException('PROOF_EXPIRED').message);
  }

  Future<SignupOutcome> submitFinal({
    required String nickname,
    required String fullName,
    String? matric,
    required String school,
    required DateTime dateOfBirth,
    String? referral,
    required String pin,
  }) async {
    if (busy) return SignupOutcome.failed;
    final pw = password;
    if (pw == null) {
      draft = await store.save(
          draft.copyWith(step: 1, clearProof: true, clearCodeSentAt: true));
      _set(error: 'Please re-enter your password to continue.');
      return SignupOutcome.failed;
    }
    if (!draft.proofIsFresh(_now())) {
      await expireProof();
      return SignupOutcome.failed;
    }

    _set(busy: true, clearError: true);
    final email = draft.email.toLowerCase();
    try {
      await api.complete(SignupSubmission(
        proof: draft.proof!,
        email: email,
        password: pw,
        phone: phoneE164,
        nickname: nickname.trim(),
        fullName: fullName.trim(),
        matric: (matric ?? '').trim().isEmpty ? null : matric!.trim(),
        school: school,
        dateOfBirth: dateOfBirth,
        referral: (referral ?? '').trim().isEmpty ? null : referral!.trim(),
        pin: pin,
      ));
    } on SignupException catch (e) {
      if (e.code == 'PROOF_USED' && await _alreadyCreated(email, pw)) {
        // The first attempt went through but its reply was lost.
        return _finishSuccess();
      }
      if (e.isProofProblem) {
        draft = await store.save(draft.copyWith(step: 2, clearProof: true));
        _set(busy: false, error: e.message);
      } else if (e.isStepOneProblem) {
        draft = await store.save(
            draft.copyWith(step: 1, clearProof: true, clearCodeSentAt: true));
        _set(busy: false, error: e.message);
      } else {
        _set(busy: false, error: e.message);
      }
      return SignupOutcome.failed;
    } catch (e) {
      _set(busy: false, error: AppErrorMapper.map(e));
      return SignupOutcome.failed;
    }

    // Account exists now. Sign in with what they typed; AuthGate does the rest.
    try {
      await signIn(email, pw);
    } catch (_) {
      await store.clear();
      draft = const SignupDraft();
      password = null;
      _set(busy: false);
      return SignupOutcome.createdButSignInFailed;
    }
    return _finishSuccess();
  }

  Future<bool> _alreadyCreated(String email, String pw) async {
    try {
      await signIn(email, pw);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<SignupOutcome> _finishSuccess() async {
    await store.clear();
    draft = const SignupDraft();
    password = null;
    _set(busy: false);
    return SignupOutcome.created;
  }

  // ── start over ─────────────────────────────────────────────────────────
  Future<void> startOver() async {
    await store.clear();
    draft = const SignupDraft();
    password = null;
    _set(busy: false, clearError: true);
  }
}
