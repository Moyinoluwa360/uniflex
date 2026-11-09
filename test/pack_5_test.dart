// Pack 5 — sign-up rebuilt: 3 steps, account created only at the end.
// Pure Dart/widget tests (no Supabase, no SMS). The server rules themselves
// (proofs, limits, atomic create) are covered by supabase/pack_5_test.sql.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/auth/screens/create_account_screen.dart';
import 'package:uniflex/shared/auth/signup/signup_api.dart';
import 'package:uniflex/shared/auth/signup/signup_draft.dart';
import 'package:uniflex/shared/auth/signup/signup_flow_controller.dart';
import 'package:uniflex/shared/auth/validators.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';

class FakeApi implements SignupApi {
  final sends = <Map<String, String>>[];
  final verifies = <String>[];
  final completes = <SignupSubmission>[];

  SignupException? sendError;
  SignupException? completeError;
  VerifyCodeResult verifyResult =
      const VerifyCodeResult(verified: true, proof: 'proof-1');
  Object? sendThrows;

  @override
  Future<SendCodeResult> sendCode({
    required String email,
    required String phone,
    required String deviceId,
  }) async {
    sends.add({'email': email, 'phone': phone, 'device': deviceId});
    if (sendThrows != null) throw sendThrows!;
    if (sendError != null) throw sendError!;
    return const SendCodeResult(cooldownSeconds: 60);
  }

  @override
  Future<VerifyCodeResult> verifyCode({
    required String phone,
    required String code,
  }) async {
    verifies.add(code);
    return verifyResult;
  }

  @override
  Future<void> complete(SignupSubmission s) async {
    completes.add(s);
    if (completeError != null) throw completeError!;
  }

  @override
  Future<bool?> isNicknameAvailable(String nickname) async => true;
  @override
  Future<bool?> isMatricAvailable(String matric) async => true;
  @override
  Future<bool?> isReferralValid(String code) async => true;
}

class Rig {
  Rig._(this.prefs, this.secrets, this.api, this.clock);

  final SharedPreferences prefs;
  final MemorySecretStore secrets;
  final FakeApi api;
  final Clock clock;
  final signIns = <List<String>>[];
  bool signInFails = false;

  static Future<Rig> create({DateTime? start}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return Rig._(prefs, MemorySecretStore(), FakeApi(),
        Clock(start ?? DateTime(2026, 11, 7, 12)));
  }

  SignupDraftStore get store =>
      SignupDraftStore(prefs, secrets, now: clock.call);

  SignupFlowController controller() => SignupFlowController(
        store: store,
        api: api,
        now: clock.call,
        signIn: (e, p) async {
          signIns.add([e, p]);
          if (signInFails) throw Exception('network');
        },
      );
}

class Clock {
  Clock(this.t);
  DateTime t;
  DateTime call() => t;
  void advance(Duration d) => t = t.add(d);
}

Future<void> toStep3(Rig r, SignupFlowController c) async {
  await c.load();
  await c.submitDetails(
      email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
  await c.verify('123456');
}

void main() {
  // ── validators / helpers ────────────────────────────────────────────
  group('phone input', () {
    test('0803… and +234803… both normalise to E.164', () {
      expect(AuthValidators.toE164('0803 123 4567'), '+2348031234567');
      expect(AuthValidators.toE164('+2348031234567'), '+2348031234567');
      expect(AuthValidators.phone('08031234567'), isNull);
      expect(AuthValidators.phone('+2348031234567'), isNull);
      expect(AuthValidators.phone('12345'), isNotNull);
    });
    test('mask hides the middle digits', () {
      expect(maskPhone('+2348031234567'), '+234 803 ••• 4567');
      expect(maskPhone('+2348031234567').contains('1234'), isFalse);
    });
    test('password/email rules unchanged', () {
      expect(AuthValidators.password('short1'), isNotNull);
      expect(AuthValidators.password('longenough'), isNotNull); // no digit
      expect(AuthValidators.password('longenough1'), isNull);
      expect(AuthValidators.email('nope'), isNotNull);
      expect(AuthValidators.email('a@b.co'), isNull);
    });
  });

  group('friendly messages', () {
    test('taken email / phone / stuck legacy account', () {
      expect(SignupException('EMAIL_TAKEN').message,
          'An account with this email already exists. Try logging in.');
      expect(SignupException('PHONE_TAKEN').message,
          contains('phone number is already used'));
      expect(SignupException('EMAIL_STUCK').message,
          contains('Log in to continue'));
    });
    test('limits', () {
      expect(SignupException('TOO_SOON', retryAfter: 42).message,
          contains('42 seconds'));
      expect(SignupException('PHONE_LIMIT').message, contains('tomorrow'));
      expect(SignupException('RATE_LIMITED').message,
          contains('Too many attempts'));
      expect(SignupException('TOO_MANY_ATTEMPTS').message,
          contains('Request a new code'));
    });
    test('never leaks raw codes; unknown → generic', () {
      expect(SignupException('WHATEVER').message, isNot(contains('WHATEVER')));
    });
    test('AppErrorMapper: SignupException + timeouts + offline', () {
      expect(AppErrorMapper.map(SignupException('EMAIL_TAKEN')),
          contains('already exists'));
      expect(AppErrorMapper.map('TimeoutException after 0:00:25'),
          contains('took too long'));
      expect(AppErrorMapper.map('SocketException: x'), contains('No internet'));
    });
  });

  // ── draft store ─────────────────────────────────────────────────────
  group('draft store', () {
    test('save → load resumes the same step and fields', () async {
      final r = await Rig.create();
      final s = r.store;
      await s.save(
        const SignupDraft(
            step: 3,
            email: 'a@b.com',
            phoneInput: '0803',
            nickname: 'nick',
            proof: 'p'),
        password: 'secret123',
      );
      final d = await r.store.load();
      expect(d!.step, 3);
      expect(d.email, 'a@b.com');
      expect(d.nickname, 'nick');
      expect(d.proof, 'p');
    });

    test('expires 24 h after the last save (and is wiped)', () async {
      final r = await Rig.create();
      await r.store.save(const SignupDraft(step: 2, email: 'a@b.com'),
          password: 'pw123456');
      r.clock.advance(const Duration(hours: 23, minutes: 59));
      expect(await r.store.load(), isNotNull);
      r.clock.advance(const Duration(minutes: 2));
      expect(await r.store.load(), isNull);
      expect(r.prefs.getString(SignupDraftStore.draftKey), isNull);
      expect(await r.store.readPassword(), isNull);
    });

    test('password lives ONLY in the secret store, never in prefs', () async {
      final r = await Rig.create();
      await r.store.save(const SignupDraft(step: 2, email: 'a@b.com'),
          password: 'Sup3rSecret!');
      expect(r.secrets.data[SignupDraftStore.passwordKey], 'Sup3rSecret!');
      for (final key in r.prefs.getKeys()) {
        expect('${r.prefs.get(key)}'.contains('Sup3rSecret!'), isFalse,
            reason: key);
      }
    });

    test('the PIN is never part of the saved draft', () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      await c.saveFinalFields(
          nickname: 'n',
          fullName: 'f',
          matric: '',
          school: "Redeemer's University",
          referral: '');
      final raw = r.prefs.getString(SignupDraftStore.draftKey)!;
      expect(raw.contains('pin'), isFalse);
      expect(raw.toLowerCase().contains('password'), isFalse);
    });

    test('clear removes draft and password', () async {
      final r = await Rig.create();
      await r.store.save(const SignupDraft(step: 2, email: 'a@b.com'),
          password: 'pw123456');
      await r.store.clear();
      expect(await r.store.load(), isNull);
      expect(await r.store.readPassword(), isNull);
    });

    test('corrupt draft is dropped, not crashed on', () async {
      final r = await Rig.create();
      await r.prefs.setString(SignupDraftStore.draftKey, '{not json');
      expect(await r.store.load(), isNull);
    });

    test('device id is stable across loads', () async {
      final r = await Rig.create();
      final a = await r.store.deviceId();
      expect(a, await r.store.deviceId());
      expect(a.length, greaterThan(20));
    });
  });

  // ── step transitions ────────────────────────────────────────────────
  group('step 1 → 2', () {
    test('moves to step 2 ONLY after the send succeeds', () async {
      final r = await Rig.create();
      final c = r.controller();
      await c.load();
      final ok = await c.submitDetails(
          email: 'A@B.com', phoneInput: '0803 123 4567', password: 'secret123');
      expect(ok, isTrue);
      expect(c.step, 2);
      expect(r.api.sends.single['phone'], '+2348031234567');
      expect(r.api.sends.single['email'], 'a@b.com'); // lower-cased
      expect(c.cooldownRemaining, 60);
    });

    test('send failure → stays on step 1, short friendly message, fields kept',
        () async {
      final r = await Rig.create();
      r.api.sendError = SignupException('EMAIL_TAKEN');
      final c = r.controller();
      await c.load();
      final ok = await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      expect(ok, isFalse);
      expect(c.step, 1);
      expect(c.error,
          'An account with this email already exists. Try logging in.');
      expect(c.draft.email, 'a@b.com');
      expect(c.busy, isFalse);
    });

    test('a network error / timeout also stays on step 1', () async {
      final r = await Rig.create();
      r.api.sendThrows = Exception('SocketException: nope');
      final c = r.controller();
      await c.load();
      expect(
        await c.submitDetails(
            email: 'a@b.com', phoneInput: '08031234567', password: 'secret123'),
        isFalse,
      );
      expect(c.step, 1);
      expect(c.error, contains('No internet'));
    });

    test(
        'TOO_SOON (code already on its way) still moves on, with the remaining wait',
        () async {
      final r = await Rig.create();
      r.api.sendError = SignupException('TOO_SOON', retryAfter: 40);
      final c = r.controller();
      await c.load();
      expect(
        await c.submitDetails(
            email: 'a@b.com', phoneInput: '08031234567', password: 'secret123'),
        isTrue,
      );
      expect(c.step, 2);
      expect(c.cooldownRemaining, inInclusiveRange(39, 40));
    });

    test('phone-taken message', () async {
      final r = await Rig.create();
      r.api.sendError = SignupException('PHONE_TAKEN');
      final c = r.controller();
      await c.load();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      expect(c.error, contains('phone number is already used'));
      expect(c.step, 1);
    });
  });

  group('step 2', () {
    test('resend is blocked for 60 s, then allowed', () async {
      final r = await Rig.create();
      final c = r.controller();
      await c.load();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      expect(await c.resend(), isFalse);
      expect(r.api.sends.length, 1); // no wasted SMS
      r.clock.advance(const Duration(seconds: 30));
      expect(c.cooldownRemaining, 30);
      expect(await c.resend(), isFalse);
      r.clock.advance(const Duration(seconds: 31));
      expect(c.cooldownRemaining, 0);
      expect(await c.resend(), isTrue);
      expect(r.api.sends.length, 2);
      expect(c.cooldownRemaining, 60);
    });

    test(
        'Change number → step 1, every field still filled, proof/cooldown dropped',
        () async {
      final r = await Rig.create();
      final c = r.controller();
      await c.load();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      await c.changeNumber();
      expect(c.step, 1);
      expect(c.draft.email, 'a@b.com');
      expect(c.draft.phoneInput, '08031234567');
      expect(c.password, 'secret123');
      expect(c.draft.proof, isNull);
      expect(c.cooldownRemaining, 0);
    });

    test('a new number gets a fresh send and discards any old verification',
        () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      expect(c.draft.proof, 'proof-1');
      await c.changeNumber();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08039999999', password: 'secret123');
      expect(r.api.sends.last['phone'], '+2348039999999');
      expect(c.draft.proof, isNull);
      expect(c.step, 2);
    });

    test('wrong code → tries-left message; stays on step 2', () async {
      final r = await Rig.create();
      r.api.verifyResult =
          const VerifyCodeResult(verified: false, attemptsLeft: 3);
      final c = r.controller();
      await c.load();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      expect(await c.verify('000000'), isFalse);
      expect(c.step, 2);
      expect(c.error, 'That code is incorrect. 3 tries left.');
    });

    test('out of tries → asks for a new code', () async {
      final r = await Rig.create();
      r.api.verifyResult =
          const VerifyCodeResult(verified: false, attemptsLeft: 0);
      final c = r.controller();
      await c.load();
      await c.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      await c.verify('000000');
      expect(c.error, contains('Request a new code'));
    });

    test('correct code → step 3 holding the proof; NO account call made',
        () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      expect(c.step, 3);
      expect(c.draft.proof, 'proof-1');
      expect(r.api.completes, isEmpty);
      expect(r.signIns, isEmpty);
    });
  });

  group('step 3', () {
    Future<SignupOutcome> submit(SignupFlowController c, {String? matric}) =>
        c.submitFinal(
          nickname: 'nick',
          fullName: 'Full Name',
          matric: matric,
          school: "Redeemer's University",
          dateOfBirth: DateTime(2004, 5, 1),
          pin: '1234',
        );

    test(
        'success: one call, signs in with the typed email+password, draft wiped',
        () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      expect(await submit(c), SignupOutcome.created);
      expect(r.api.completes.single.proof, 'proof-1');
      expect(r.api.completes.single.pin, '1234');
      expect(r.api.completes.single.phone, '+2348031234567');
      expect(r.signIns.single, ['a@b.com', 'secret123']);
      expect(await r.store.load(), isNull);
      expect(await r.store.readPassword(), isNull);
    });

    test('expired proof → back to step 2, other details kept, NO server call',
        () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      await c.saveFinalFields(
          nickname: 'nick',
          fullName: 'Full',
          matric: '',
          school: "Redeemer's University",
          referral: '');
      r.clock.advance(const Duration(minutes: 30));
      expect(await submit(c), SignupOutcome.failed);
      expect(c.step, 2);
      expect(c.draft.proof, isNull);
      expect(c.draft.email, 'a@b.com');
      expect(c.draft.nickname, 'nick');
      expect(c.error, contains('verification expired'));
      expect(r.api.completes, isEmpty);
    });

    test('expireProof (timer) sends step 3 back to step 2', () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      await c.expireProof();
      expect(c.step, 2);
    });

    test('server rejects the proof → step 2', () async {
      final r = await Rig.create();
      r.api.completeError = SignupException('PROOF_EXPIRED');
      final c = r.controller();
      await toStep3(r, c);
      expect(await submit(c), SignupOutcome.failed);
      expect(c.step, 2);
      expect(r.signIns, isEmpty);
    });

    test('nickname taken → stays on step 3 with the message', () async {
      final r = await Rig.create();
      r.api.completeError = SignupException('NICKNAME_TAKEN');
      final c = r.controller();
      await toStep3(r, c);
      await submit(c);
      expect(c.step, 3);
      expect(c.error, contains('nickname is taken'));
    });

    test('email taken at the last moment → back to step 1', () async {
      final r = await Rig.create();
      r.api.completeError = SignupException('EMAIL_TAKEN');
      final c = r.controller();
      await toStep3(r, c);
      await submit(c);
      expect(c.step, 1);
      expect(c.error, contains('already exists'));
    });

    test(
        'reply lost on the first try: PROOF_USED + sign-in works → treated as created',
        () async {
      final r = await Rig.create();
      r.api.completeError = SignupException('PROOF_USED');
      final c = r.controller();
      await toStep3(r, c);
      expect(await submit(c), SignupOutcome.created);
      expect(r.signIns.single, ['a@b.com', 'secret123']);
    });

    test('account created but sign-in fails → told to log in; draft wiped',
        () async {
      final r = await Rig.create();
      r.signInFails = true;
      final c = r.controller();
      await toStep3(r, c);
      expect(await submit(c), SignupOutcome.createdButSignInFailed);
      expect(await r.store.load(), isNull);
    });
  });

  group('resume / start over', () {
    test('reopen at step 2 resumes step 2 with the phone and countdown',
        () async {
      final r = await Rig.create();
      final c1 = r.controller();
      await c1.load();
      await c1.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
      r.clock.advance(const Duration(seconds: 20));
      final c2 = r.controller();
      await c2.load();
      expect(c2.step, 2);
      expect(c2.password, 'secret123');
      expect(c2.cooldownRemaining, 40);
    });

    test('reopen at step 3 with a fresh proof resumes step 3', () async {
      final r = await Rig.create();
      await toStep3(r, r.controller());
      r.clock.advance(const Duration(minutes: 10));
      final c2 = r.controller();
      await c2.load();
      expect(c2.step, 3);
    });

    test('reopen at step 3 after the proof expired → step 2, details kept',
        () async {
      final r = await Rig.create();
      await toStep3(r, r.controller());
      r.clock.advance(const Duration(minutes: 31));
      final c2 = r.controller();
      await c2.load();
      expect(c2.step, 2);
      expect(c2.draft.email, 'a@b.com');
    });

    test('draft older than 24 h is gone → fresh step 1', () async {
      final r = await Rig.create();
      await toStep3(r, r.controller());
      r.clock.advance(const Duration(hours: 25));
      final c2 = r.controller();
      await c2.load();
      expect(c2.step, 1);
      expect(c2.draft.email, '');
    });

    test('keystore lost the password → resumes at step 1 to re-type it',
        () async {
      final r = await Rig.create();
      await toStep3(r, r.controller());
      r.secrets.data.clear();
      final c2 = r.controller();
      await c2.load();
      expect(c2.step, 1);
      expect(c2.draft.email, 'a@b.com');
    });

    test('Start over clears everything', () async {
      final r = await Rig.create();
      final c = r.controller();
      await toStep3(r, c);
      await c.startOver();
      expect(c.step, 1);
      expect(c.hasProgress, isFalse);
      expect(await r.store.load(), isNull);
      expect(await r.store.readPassword(), isNull);
    });
  });

  // ── widgets: the exact bug report ───────────────────────────────────
  group('widgets', () {
    Future<void> boot(WidgetTester t, SignupFlowController c) async {
      await t.pumpWidget(MaterialApp(home: CreateAccountScreen(controller: c)));
      await t.pumpAndSettle();
    }

    Future<void> fillStep1(WidgetTester t) async {
      await t.enterText(find.byType(TextFormField).at(0), 'a@b.com');
      await t.enterText(find.byType(TextFormField).at(1), 'secret123');
      await t.enterText(find.byType(TextFormField).at(2), 'secret123');
      await t.enterText(find.byType(TextFormField).at(3), '08031234567');
    }

    Future<void> tapContinue(WidgetTester t) async {
      await t.ensureVisible(find.text('Continue'));
      await t.tap(find.text('Continue'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
    }

    testWidgets(
        'SMS sent → the app MOVES to the code screen (the reported bug)',
        (t) async {
      final r = await Rig.create();
      final c = r.controller();
      await boot(t, c);
      expect(find.text('Create your\naccount'), findsOneWidget);

      await fillStep1(t);
      await tapContinue(t);

      expect(find.text('Verify your\nphone'), findsOneWidget);
      expect(find.byKey(const ValueKey('masked-phone')), findsOneWidget);
      expect(find.textContaining('+234 803 ••• 4567'), findsOneWidget);
      expect(r.api.sends.length, 1); // exactly one SMS
      expect(r.signIns, isEmpty); // and no account/session yet
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('send fails → stays on step 1 with a short message', (t) async {
      final r = await Rig.create();
      r.api.sendError = SignupException('EMAIL_TAKEN');
      final c = r.controller();
      await boot(t, c);
      await fillStep1(t);
      await tapContinue(t);

      expect(find.text('Create your\naccount'), findsOneWidget);
      expect(
          find.text(
              'An account with this email already exists. Try logging in.'),
          findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('resend is disabled with a visible countdown', (t) async {
      final r = await Rig.create();
      final c = r.controller();
      await boot(t, c);
      await fillStep1(t);
      await tapContinue(t);

      expect(find.text('Resend code in 1:00'), findsOneWidget);
      final button = t.widget<AppButton>(find.byKey(const ValueKey('resend')));
      expect(button.onPressed, isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Change number returns to step 1 with the fields filled',
        (t) async {
      final r = await Rig.create();
      final c = r.controller();
      await boot(t, c);
      await fillStep1(t);
      await tapContinue(t);

      await t.tap(find.byKey(const ValueKey('change-number')));
      await t.pumpAndSettle();

      expect(find.text('Create your\naccount'), findsOneWidget);
      expect(find.text('a@b.com'), findsOneWidget);
      expect(find.text('08031234567'), findsOneWidget);
      expect(find.text('secret123'), findsNWidgets(2));
    });

    testWidgets('reopening mid-signup resumes on the code screen', (t) async {
      final r = await Rig.create();
      final c1 = r.controller();
      await c1.load();
      await c1.submitDetails(
          email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');

      final c2 = r.controller();
      await boot(t, c2);
      expect(find.text('Verify your\nphone'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('"Start over" appears only when there is a draft', (t) async {
      final r = await Rig.create();
      final c = r.controller();
      await boot(t, c);
      expect(find.byKey(const ValueKey('start-over')), findsNothing);
      await fillStep1(t);
      await tapContinue(t);
      await t.tap(find.byKey(const ValueKey('change-number')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-over')), findsOneWidget);
      await t.ensureVisible(find.byKey(const ValueKey('start-over')));
      await t.tap(find.byKey(const ValueKey('start-over')));
      await t.pumpAndSettle();
      expect(find.text('a@b.com'), findsNothing);
      expect(find.byKey(const ValueKey('start-over')), findsNothing);
    });
  });
}
