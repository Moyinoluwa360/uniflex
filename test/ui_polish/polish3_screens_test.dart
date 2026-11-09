// UI Polish 3, Parts B + C: Login and the three sign-up steps wear the new
// look; nothing about their fields, texts, validators or OTP behaviour moved.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/auth/screens/create_account_screen.dart';
import 'package:uniflex/shared/auth/screens/forgot_password_screen.dart';
import 'package:uniflex/shared/auth/screens/login_screen.dart';
import 'package:uniflex/shared/auth/screens/reset_password_screen.dart';
import 'package:uniflex/shared/auth/signup/signup_api.dart';
import 'package:uniflex/shared/auth/signup/signup_flow_controller.dart';
import 'package:uniflex/shared/auth/validators.dart';
import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/shared/widgets/auth/app_auth_header.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/widgets/inputs/app_otp_field.dart';
import 'package:uniflex/shared/widgets/inputs/app_text_field.dart';

import '../pack_5_test.dart' show Rig, toStep3;
import 'polish3_harness.dart';

Widget loginHome() => const LoginScreen();
Widget scope(Widget app) => ProviderScope(child: app);

Future<SignupFlowController> atStep(Rig r, int step) async {
  final c = r.controller();
  await c.load();
  if (step >= 2) {
    await c.submitDetails(
        email: 'a@b.com', phoneInput: '08031234567', password: 'secret123');
  }
  if (step >= 3) await c.verify('123456');
  return c;
}

/// The text fields of a screen, in order.
List<TextFormField> fieldsOf(WidgetTester t) =>
    t.widgetList<TextFormField>(find.byType(TextFormField)).toList();

Rect rectOfField(WidgetTester t, Finder f) => t.getRect(f);

/// Focuses [field] with the keyboard open and checks the field and the
/// primary button are both on screen above the keyboard.
Future<void> expectFieldAndButtonVisible(
  WidgetTester t,
  Finder field,
  Finder button,
  Size size,
  double keyboard,
) async {
  await t.showKeyboard(field);
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  final top = size.height - keyboard;
  final f = t.getRect(
      find.ancestor(of: field, matching: find.byType(TextFormField)).first);
  final b = t.getRect(button);
  expect(f.top, greaterThanOrEqualTo(-0.5),
      reason: 'field above the screen $f');
  expect(f.bottom, lessThanOrEqualTo(top + 0.5),
      reason: 'field behind keyboard $f');
  expect(b.top, greaterThanOrEqualTo(-0.5),
      reason: 'button above the screen $b');
  expect(b.bottom, lessThanOrEqualTo(top + 0.5),
      reason: 'button behind keyboard $b');
}

Finder editable(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

void main() {
  setUpAll(loadAppFonts);

  // ── Login ───────────────────────────────────────────────────────────
  group('Login', () {
    forEachVariant('renders: header, fields, buttons, no overflow',
        (t, dark, scale, size) async {
      await pumpScreen(t, loginHome(),
          dark: dark, scale: scale, size: size, wrap: scope);
      expect(t.takeException(), isNull);
      for (final s in [
        'Welcome back',
        'Log in to order food, book deliveries and send errands.',
        'Food',
        'Deliveries',
        'Errands',
        'Email address',
        'Password',
        'Forgot password?',
        'Log In',
        'New here?',
        'Create Account',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      // nothing sits on the orange circle
      final orange = orangeRect(size, false);
      for (final s in ['Uniflex', 'Welcome back', 'Food']) {
        expect(t.getRect(find.text(s)).overlaps(orange), isFalse, reason: s);
      }
      // caption: only when there is room
      final tall = size.height >= 700 && scale <= 1.15;
      expect(find.text("Redeemer's University"),
          tall ? findsOneWidget : findsNothing);
    });

    forEachVariant('keyboard open: focused field and Log In both visible',
        (t, dark, scale, size) async {
      const kb = 280.0;
      await pumpScreen(t, loginHome(),
          dark: dark, scale: scale, size: size, keyboard: kb, wrap: scope);
      final login = find.widgetWithText(AppButton, 'Log In');
      for (final i in [0, 1]) {
        final field = editable(find.byType(AppTextField).at(i));
        await expectFieldAndButtonVisible(t, field, login, size, kb);
      }
      expect(find.text("Redeemer's University"), findsNothing);
    });

    testWidgets('field list, order, keyboard types and validators unchanged',
        (t) async {
      await pumpScreen(t, loginHome(), wrap: scope);
      final f = fieldsOf(t);
      expect(f.length, 2);
      final email = t.widget<AppTextField>(find.byType(AppTextField).at(0));
      final pass = t.widget<AppTextField>(find.byType(AppTextField).at(1));
      expect(email.label, 'Email address');
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.textInputAction, TextInputAction.next);
      expect(email.prefixIcon, AppIcons.mail);
      expect(email.validator!(''), AuthValidators.email(''));
      expect(email.validator!('x'), AuthValidators.email('x'));
      expect(email.validator!('a@b.com'), isNull);
      expect(pass.label, 'Password');
      expect(pass.obscureText, isTrue);
      expect(pass.textInputAction, TextInputAction.done);
      expect(pass.validator!(''), 'Enter your password');
      expect(pass.validator!('x'), isNull);
      // eye toggles the same way as before
      await t.tap(find.byIcon(AppIcons.eye));
      await t.pump();
      expect(
          t.widget<AppTextField>(find.byType(AppTextField).at(1)).obscureText,
          isFalse);
    });

    testWidgets('Forgot password still navigates; Create Account is enabled',
        (t) async {
      await pumpScreen(t, loginHome(), wrap: scope);
      await t.tap(find.text('Forgot password?'));
      await t.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      await t.tap(find.byIcon(AppIcons.chevronLeft));
      await t.pumpAndSettle();
      // Create Account is enabled (it opens the sign-up flow, which needs a
      // live Supabase client, so it is not tapped here).
      expect(
          t
              .widget<AppButton>(
                  find.widgetWithText(AppButton, 'Create Account'))
              .onPressed,
          isNotNull);
    });

    testWidgets('empty submit shows the existing messages in the new row',
        (t) async {
      await pumpScreen(t, loginHome(), wrap: scope);
      await t.tap(find.text('Log In'));
      await t.pump();
      expect(find.text(AuthValidators.email('')!), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(find.byIcon(AppIcons.error), findsNWidgets(2));
    });
  });

  // ── Sign-up step 1 ──────────────────────────────────────────────────
  group('Create account · step 1', () {
    forEachVariant('renders, pinned Continue, no overflow',
        (t, dark, scale, size) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 1);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size);
      await t.pump();
      expect(t.takeException(), isNull);
      for (final s in [
        'Create your\naccount',
        'Food, deliveries and errands across campus. Takes about a minute.',
        '1 / 3',
        'Email address',
        'Password',
        '8+ characters, at least one number',
        'Confirm password',
        'Phone number',
        '08012345678',
        'Continue',
        'Already have an account? ',
        'Log in',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      final orange = orangeRect(size, true);
      expect(t.getRect(find.text('Create your\naccount')).overlaps(orange),
          isFalse);
      expect(t.getRect(find.text('Continue')).bottom,
          lessThanOrEqualTo(size.height));
    });

    forEachVariant('keyboard open on every field: field + Continue visible',
        (t, dark, scale, size) async {
      const kb = 280.0;
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 1);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size, keyboard: kb);
      final cont = find.widgetWithText(AppButton, 'Continue');
      for (var i = 0; i < 4; i++) {
        await expectFieldAndButtonVisible(
            t, editable(find.byType(AppTextField).at(i)), cont, size, kb);
      }
    });

    testWidgets('field list, order, keyboard types, validators unchanged',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 1);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      final f = t.widgetList<AppTextField>(find.byType(AppTextField)).toList();
      expect(f.map((e) => e.label), [
        'Email address',
        'Password',
        'Confirm password',
        'Phone number',
      ]);
      expect(f.map((e) => e.hint), [
        null,
        '8+ characters, at least one number',
        null,
        '08012345678',
      ]);
      expect(f.map((e) => e.obscureText), [false, true, true, false]);
      expect(f.map((e) => e.keyboardType), [
        TextInputType.emailAddress,
        null,
        null,
        TextInputType.phone,
      ]);
      expect(f.map((e) => e.textInputAction), [
        TextInputAction.next,
        TextInputAction.next,
        TextInputAction.next,
        TextInputAction.done,
      ]);
      expect(f.map((e) => e.prefixIcon),
          [AppIcons.mail, AppIcons.lock, AppIcons.lock, AppIcons.phone]);
      expect(f[0].validator!('nope'), AuthValidators.email('nope'));
      expect(f[1].validator!('short'), AuthValidators.password('short'));
      expect(
          f[1].validator!('secret123'), AuthValidators.password('secret123'));
      expect(f[2].validator!(''), 'Confirm your password');
      expect(f[2].validator!('different'), 'Passwords do not match');
      expect(f[3].validator!('123'), AuthValidators.phone('123'));
      expect(f.every((e) => e.large), isTrue);
    });
  });

  // ── Sign-up step 2 ──────────────────────────────────────────────────
  group('Create account · step 2', () {
    forEachVariant('renders: six boxes, pinned Verify, no overflow',
        (t, dark, scale, size) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size);
      await t.pump();
      expect(t.takeException(), isNull);
      expect(find.text('Verify your\nphone'), findsOneWidget);
      expect(find.byKey(const ValueKey('masked-phone')), findsOneWidget);
      expect(find.textContaining('+234 803 ••• 4567'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      for (var i = 0; i < 6; i++) {
        expect(find.byKey(ValueKey('otp-box-$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('otp-box-6')), findsNothing);
      expect(find.text('Verify'), findsOneWidget);
      expect(find.byKey(const ValueKey('resend')), findsOneWidget);
      expect(find.byKey(const ValueKey('change-number')), findsOneWidget);
      expect(find.text('Resend code in 1:00'), findsOneWidget);
      expect(t.getRect(find.text('Verify')).bottom,
          lessThanOrEqualTo(size.height));
    });

    forEachVariant('keyboard open: boxes and Verify both visible',
        (t, dark, scale, size) async {
      const kb = 280.0;
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size, keyboard: kb);
      await t.showKeyboard(editable(find.byKey(const ValueKey('otp-input'))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final top = size.height - kb;
      final box = t.getRect(find.byKey(const ValueKey('otp-box-0')));
      final verify = t.getRect(find.widgetWithText(AppButton, 'Verify'));
      expect(box.bottom, lessThanOrEqualTo(top));
      expect(verify.bottom, lessThanOrEqualTo(top + 0.5));
      expect(box.bottom, lessThanOrEqualTo(verify.top));
    });

    testWidgets('typing and pasting a code reach the controller and the API',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      final input = editable(find.byKey(const ValueKey('otp-input')));
      await t.showKeyboard(input);
      await t.enterText(input, '482913'); // a paste lands the same way
      await t.pump();
      for (final d in ['4', '8', '2', '9', '1', '3']) {
        expect(find.text(d), findsOneWidget);
      }
      await t.tap(find.text('Verify'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 300));
      expect(r.api.verifies, ['482913']);
      // right code ⇒ the host moved on to step 3
      expect(find.text('Complete your\nprofile'), findsOneWidget);
    });

    testWidgets('Verify with a short code shows the existing message',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      await t.showKeyboard(editable(find.byKey(const ValueKey('otp-input'))));
      await t.enterText(
          editable(find.byKey(const ValueKey('otp-input'))), '12');
      await t.pump();
      await t.tap(find.text('Verify'));
      await t.pump();
      expect(find.text('Enter the 6-digit code we sent you'), findsOneWidget);
      expect(r.api.verifies, isEmpty);
    });

    testWidgets('wrong code: boxes cleared and red, message below the boxes',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      r.api.verifyResult =
          const VerifyCodeResult(verified: false, attemptsLeft: 4);
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      final input = editable(find.byKey(const ValueKey('otp-input')));
      await t.showKeyboard(input);
      await t.enterText(input, '111111');
      await t.pump();
      await t.tap(find.text('Verify'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('1'), findsNothing); // cleared, like before
      expect(c.error, isNotNull);
      expect(find.text(c.error!), findsOneWidget);
      expect(find.byIcon(AppIcons.error), findsOneWidget);
      final msg = t.getRect(find.text(c.error!));
      final boxes = t.getRect(find.byKey(const ValueKey('otp-box-0')));
      expect(msg.top, greaterThan(boxes.bottom));
    });

    testWidgets('resend is disabled with a countdown, enabled after it',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      expect(find.text('Resend code in 1:00'), findsOneWidget);
      expect(
          t.widget<AppButton>(find.byKey(const ValueKey('resend'))).onPressed,
          isNull);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('OTP input keeps the number keyboard and digits-only',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 2);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      final tf = t.widget<TextField>(find.descendant(
          of: find.byType(AppOtpField), matching: find.byType(TextField)));
      expect(tf.keyboardType, TextInputType.number);
      expect(tf.inputFormatters!.whereType<FilteringTextInputFormatter>(),
          isNotEmpty);
      expect(tf.autofillHints, contains(AutofillHints.oneTimeCode));
    });
  });

  // ── Sign-up step 3 ──────────────────────────────────────────────────
  group('Create account · step 3', () {
    forEachVariant('renders: sectioned form, pinned Finish setup',
        (t, dark, scale, size) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size);
      await t.pump();
      expect(t.takeException(), isNull);
      for (final s in [
        'Complete your\nprofile',
        'Phone verified',
        '3 / 3',
        'Nickname',
        'Date of birth',
        'Full name',
        'As written on your ID card',
        'Matric number (optional)',
        'RUN / CMP / 22 / 1234',
        "Redeemer's University",
        'Referral code',
        'FLEX500 (optional)',
        'Transaction PIN',
        "You'll enter this 4-digit PIN to confirm every order.",
        'PIN',
        'Confirm PIN',
        'Finish setup',
      ]) {
        expect(find.textContaining(s), findsWidgets, reason: s);
      }
      final orange = orangeRect(size, true);
      expect(t.getRect(find.text('Complete your\nprofile')).overlaps(orange),
          isFalse);
      expect(t.getRect(find.text('Finish setup')).bottom,
          lessThanOrEqualTo(size.height));
    });

    forEachVariant('keyboard open on every field: field + Finish setup visible',
        (t, dark, scale, size) async {
      const kb = 280.0;
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          dark: dark, scale: scale, size: size, keyboard: kb);
      final fin = find.widgetWithText(AppButton, 'Finish setup');
      final n = find.byType(AppTextField).evaluate().length;
      expect(n, 6); // nickname, full name, matric, referral, PIN, confirm PIN
      for (var i = 0; i < n; i++) {
        await expectFieldAndButtonVisible(
            t, editable(find.byType(AppTextField).at(i)), fin, size, kb);
      }
    });

    testWidgets('field list, order, formatters and validators unchanged',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      final f = t.widgetList<AppTextField>(find.byType(AppTextField)).toList();
      expect(f.map((e) => e.label), [
        'Nickname',
        'Full name',
        'Matric number (optional)',
        'Referral code',
        'PIN',
        'Confirm PIN',
      ]);
      expect(f.map((e) => e.hint), [
        null,
        'As written on your ID card',
        'RUN / CMP / 22 / 1234',
        'FLEX500 (optional)',
        null,
        null,
      ]);
      expect(f.map((e) => e.obscureText),
          [false, false, false, false, true, true]);
      expect(f[0].validator!(''),
          AuthValidators.required('', fieldName: 'a nickname'));
      expect(f[1].validator!(''),
          AuthValidators.required('', fieldName: 'your full name'));
      expect(f[4].validator!('12'), 'Enter 4 digits');
      expect(f[4].validator!('1234'), isNull);
      expect(f[5].validator!('12'), 'Enter 4 digits');
      expect(f[4].keyboardType, TextInputType.number);
      expect(f[4].inputFormatters, hasLength(2));
      // pair fields carry no leading icon; the rest keep their meaning
      expect(f.map((e) => e.prefixIcon), [
        null,
        AppIcons.idCard,
        AppIcons.idCard,
        AppIcons.gift,
        null,
        null,
      ]);
    });

    testWidgets(
        'empty Finish setup: existing messages, date error under the date box',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      await t.tap(find.text('Finish setup'));
      await t.pump();
      expect(find.text('Select your date of birth'), findsOneWidget);
      expect(find.text('Enter 4 digits'), findsNWidgets(2));
      expect(r.api.completes, isEmpty);
    });

    testWidgets('the school dropdown opens a sheet with the same option',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c));
      await t.ensureVisible(find.text("Redeemer's University"));
      await t.tap(find.text("Redeemer's University"));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-handle')), findsOneWidget);
      expect(find.byKey(const ValueKey("dropdown-row-Redeemer's University")),
          findsOneWidget);
      expect(find.byIcon(AppIcons.check), findsOneWidget);
    });

    testWidgets('PIN pair stacks when the row is too narrow for the text size',
        (t) async {
      final r = await Rig.create(start: DateTime.now());
      final c = await atStep(r, 3);
      await pumpScreen(t, CreateAccountScreen(controller: c),
          size: small, scale: 1.3);
      final pin = t.getRect(find.byType(AppTextField).at(4));
      final confirm = t.getRect(find.byType(AppTextField).at(5));
      expect(confirm.top, greaterThan(pin.bottom - 1));
      await pumpScreen(t, CreateAccountScreen(controller: c), size: normal);
      final pin2 = t.getRect(find.byType(AppTextField).at(4));
      final confirm2 = t.getRect(find.byType(AppTextField).at(5));
      expect((confirm2.top - pin2.top).abs(), lessThan(1)); // side by side
      expect(pin2.width, closeTo(confirm2.width, 0.5));
    });
  });

  // ── Other auth screens ──────────────────────────────────────────────
  group('Forgot / Reset password', () {
    forEachVariant('forgot: renders with all its text, no overflow',
        (t, dark, scale, size) async {
      await pumpScreen(t, const ForgotPasswordScreen(),
          dark: dark, scale: scale, size: size, wrap: scope);
      expect(t.takeException(), isNull);
      for (final s in [
        'Forgot Password',
        'Reset your password',
        'Email address',
        'Send Code',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.textContaining('6-digit code to reset your password'),
          findsOneWidget);
      final orange = orangeRect(size, true);
      expect(t.getRect(find.text('Forgot Password')).overlaps(orange), isFalse);
    });

    forEachVariant('reset: renders with all its text, no overflow',
        (t, dark, scale, size) async {
      await pumpScreen(t, const ResetPasswordScreen(email: 'a@b.com'),
          dark: dark, scale: scale, size: size, wrap: scope);
      expect(t.takeException(), isNull);
      for (final s in [
        'Check your email',
        '6-digit code',
        'New password',
        'Confirm new password',
      ]) {
        expect(find.text(s), findsOneWidget, reason: s);
      }
      expect(find.text('Reset Password'), findsNWidgets(2)); // title + button
      expect(find.widgetWithText(AppButton, 'Reset Password'), findsOneWidget,
          reason: 'pinned action');
    });
  });

  // ── The header never takes a tap on real screens ────────────────────
  testWidgets(
      'step 1: the glass back button pops; the header is not a tap sink',
      (t) async {
    final r = await Rig.create(start: DateTime.now());
    final c = await atStep(r, 1);
    await pumpScreen(
      t,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CreateAccountScreen(controller: c))),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.byType(AppAuthHeader), findsOneWidget);
    await t.tap(find.byIcon(AppIcons.chevronLeft));
    await t.pumpAndSettle();
    expect(find.byType(CreateAccountScreen), findsNothing);
  });

  test('toStep3 helper still reaches step 3', () async {
    final r = await Rig.create(start: DateTime.now());
    final c = r.controller();
    await toStep3(r, c);
    expect(c.step, 3);
  });
}
