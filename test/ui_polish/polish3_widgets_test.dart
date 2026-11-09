// UI Polish 3, Part A: the shared auth/form pieces. Both themes, text scale
// 1.0 / 1.3, a small phone (320x568) and a normal one (390x844).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/widgets/auth/app_auth_header.dart';
import 'package:uniflex/shared/widgets/auth/auth_scaffold.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/widgets/inputs/app_form_parts.dart';
import 'package:uniflex/shared/widgets/inputs/app_otp_field.dart';
import 'package:uniflex/shared/widgets/inputs/app_picker_field.dart';
import 'package:uniflex/shared/widgets/inputs/app_text_field.dart';

/// The real fonts, so text widths are realistic (tests default to a box font).
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final e in {
    'PlusJakartaSans': [
      'PlusJakartaSans-Regular.ttf',
      'PlusJakartaSans-Medium.ttf',
      'PlusJakartaSans-SemiBold.ttf',
      'PlusJakartaSans-Bold.ttf',
    ],
    'ClashDisplay': ['ClashDisplay-Semibold.ttf'],
  }.entries) {
    final l = FontLoader(e.key);
    for (final f in e.value) {
      l.addFont(Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }
}

const small = Size(320, 568);
const normal = Size(390, 844);

Future<void> pumpScreen(
  WidgetTester t,
  Widget home, {
  bool dark = false,
  double scale = 1.0,
  Size size = normal,
  double keyboard = 0,
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, w) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: w!,
    ),
    home: home,
  ));
  await t.pump();
}

void forEachVariant(
  String name,
  Future<void> Function(WidgetTester t, bool dark, double scale, Size size)
      body,
) {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      for (final size in [small, normal]) {
        testWidgets(
            '$name (${dark ? 'dark' : 'light'}, x$scale, ${size.width.toInt()}x${size.height.toInt()})',
            (t) => body(t, dark, scale, size));
      }
    }
  }
}

Rect orangeRect(Size size, bool compact) {
  final reach = AppAuthHeader.accentReach(compact);
  final depth = AppAuthHeader.accentDepth(compact);
  return Rect.fromLTRB(size.width - reach, 0, size.width, depth);
}

void main() {
  setUpAll(loadAppFonts);

  group('AppAuthHeader', () {
    forEachVariant('login: no overflow, no text on the orange circle',
        (t, dark, scale, size) async {
      await pumpScreen(
        t,
        const Scaffold(
          body: SingleChildScrollView(
            child: AppAuthHeader.login(
              headline: 'Welcome back',
              subtitle:
                  'Log in to order food, book deliveries and send errands.',
              chips: [
                AuthHeaderChip(AppIcons.food, 'Food'),
                AuthHeaderChip(AppIcons.delivery, 'Deliveries'),
                AuthHeaderChip(AppIcons.errand, 'Errands'),
              ],
            ),
          ),
        ),
        dark: dark,
        scale: scale,
        size: size,
      );
      expect(t.takeException(), isNull);
      final orange = orangeRect(size, false);
      for (final f in [
        find.text('Uniflex'),
        find.text('Welcome back'),
        find.text('Log in to order food, book deliveries and send errands.'),
        find.text('Food'),
        find.text('Deliveries'),
        find.text('Errands'),
      ]) {
        expect(f, findsOneWidget);
        final r = t.getRect(f);
        expect(r.overlaps(orange), isFalse,
            reason: 'text $r overlaps the orange circle $orange');
        expect(r.right, lessThanOrEqualTo(size.width));
      }
    });

    forEachVariant('compact: progress, no overflow, no text on the circle',
        (t, dark, scale, size) async {
      await pumpScreen(
        t,
        Scaffold(
          body: SingleChildScrollView(
            child: AppAuthHeader.compact(
              title: 'Complete your\nprofile',
              subtitle: 'Phone verified',
              onBack: () {},
              step: 2,
              totalSteps: 3,
              stepLabel: '2 / 3',
            ),
          ),
        ),
        dark: dark,
        scale: scale,
        size: size,
      );
      expect(t.takeException(), isNull);
      final orange = orangeRect(size, true);
      for (final f in [
        find.text('Complete your\nprofile'),
        find.text('Phone verified'),
        find.text('2 / 3'),
      ]) {
        expect(t.getRect(f).overlaps(orange), isFalse);
      }
      final h = t.ensureSemantics();
      await t.pump();
      expect(find.bySemanticsLabel(RegExp('Step 2 of 3')), findsOneWidget);
      h.dispose();
    });

    testWidgets('decorations never take a tap; the back button works',
        (t) async {
      var back = 0;
      var parentTaps = 0;
      await pumpScreen(
        t,
        Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => parentTaps++,
            child: Align(
              alignment: Alignment.topCenter,
              child: AppAuthHeader.compact(
                title: 'T',
                onBack: () => back++,
                step: 1,
                totalSteps: 3,
              ),
            ),
          ),
        ),
      );
      // The decoration layer is ignored by hit testing…
      final ignoring = t
          .widgetList<IgnorePointer>(find.descendant(
              of: find.byType(AppAuthHeader),
              matching: find.byType(IgnorePointer)))
          .where((i) => i.ignoring);
      expect(ignoring, isNotEmpty);
      // …so a tap on the orange circle falls through to whatever is behind.
      await t.tapAt(Offset(normal.width - 30, 30));
      expect(parentTaps, 1);
      await t.tap(find.byIcon(AppIcons.chevronLeft));
      expect(back, 1);
    });

    testWidgets('a null onBack dims the back button and does nothing',
        (t) async {
      await pumpScreen(
        t,
        const Scaffold(body: AppAuthHeader.compact(title: 'T')),
      );
      await t.tap(find.byIcon(AppIcons.chevronLeft));
      expect(t.takeException(), isNull);
    });
  });

  group('AppTextField large', () {
    Widget form({
      String? error,
      bool obscure = false,
      bool locked = false,
      IconData? icon = AppIcons.mail,
      String? hint,
      String label = 'Email address',
      Widget? suffix,
    }) =>
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(children: [
                AppTextField(
                  key: const ValueKey('f'),
                  large: true,
                  label: label,
                  hint: hint,
                  prefixIcon: icon,
                  obscureText: obscure,
                  errorText: error,
                  readOnly: locked,
                  suffixIcon: suffix,
                ),
              ]),
            ),
          ),
        );

    forEachVariant('states render without overflow',
        (t, dark, scale, size) async {
      for (final cfg in <Widget>[
        form(),
        form(hint: '8+ characters, at least one number'),
        form(error: 'Enter a valid email address'),
        form(locked: true),
        form(
            obscure: true,
            suffix:
                IconButton(onPressed: () {}, icon: const Icon(AppIcons.eye))),
        form(icon: null),
      ]) {
        await pumpScreen(t, cfg, dark: dark, scale: scale, size: size);
        expect(t.takeException(), isNull);
      }
    });

    testWidgets(
        '56 high, label becomes the in-box placeholder, hint becomes helper',
        (t) async {
      await pumpScreen(t, form(hint: 'A helper'));
      expect(t.getSize(find.byKey(const ValueKey('f'))).height,
          greaterThanOrEqualTo(56));
      expect(find.text('Email address'), findsOneWidget);
      expect(find.text('A helper'), findsOneWidget);
      // box is 56 high (the field minus its helper line)
      final box = t.getRect(find.byType(InputDecorator));
      expect(box.height, greaterThanOrEqualTo(56));
    });

    testWidgets('error shows an alert icon and the message', (t) async {
      await pumpScreen(t, form(error: 'Nope'));
      expect(find.text('Nope'), findsOneWidget);
      expect(find.byIcon(AppIcons.error), findsOneWidget);
    });

    testWidgets('validator errors use the same row', (t) async {
      final key = GlobalKey<FormState>();
      await pumpScreen(
        t,
        Scaffold(
          body: Form(
            key: key,
            child: AppTextField(
              large: true,
              label: 'Name',
              validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
            ),
          ),
        ),
      );
      expect(key.currentState!.validate(), isFalse);
      await t.pump();
      expect(find.text('Required'), findsOneWidget);
      expect(find.byIcon(AppIcons.error), findsOneWidget);
    });

    testWidgets('locked field shows the lock', (t) async {
      await pumpScreen(t, form(locked: true));
      expect(find.byIcon(AppIcons.lock), findsOneWidget);
    });
  });

  group('AppPickerField / AppDropdownField', () {
    forEachVariant('render without overflow', (t, dark, scale, size) async {
      await pumpScreen(
        t,
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              AppPickerField(
                  placeholder: 'Date of birth',
                  onTap: () {},
                  errorText: 'Pick one'),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                label: 'Region / School',
                value: 'A',
                items: const [AppDropdownItem('A', "Redeemer's University")],
                onChanged: (_) {},
              ),
            ]),
          ),
        ),
        dark: dark,
        scale: scale,
        size: size,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('dropdown opens an AppSheet with 56-high rows and a check',
        (t) async {
      String? picked;
      await pumpScreen(
        t,
        Scaffold(
          body: AppDropdownField<String>(
            label: 'Region / School',
            value: 'A',
            items: const [
              AppDropdownItem('A', 'Alpha'),
              AppDropdownItem('B', 'Beta'),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      );
      await t.tap(find.text('Alpha'));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-handle')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey('dropdown-row-Beta'))).height,
          56);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('dropdown-row-Alpha')),
              matching: find.byIcon(AppIcons.check)),
          findsOneWidget);
      await t.tap(find.text('Beta'));
      await t.pumpAndSettle();
      expect(picked, 'B');
    });
  });

  group('AppOtpField', () {
    Widget host(TextEditingController c,
            {int length = 6,
            String? error,
            ValueChanged<String>? onChanged,
            ValueChanged<String>? onCompleted}) =>
        Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: AppOtpField(
              controller: c,
              length: length,
              errorText: error,
              onChanged: onChanged,
              onCompleted: onCompleted,
            ),
          ),
        );

    forEachVariant('empty / partial / full / error',
        (t, dark, scale, size) async {
      final c = TextEditingController();
      for (final text in ['', '12', '123456']) {
        c.text = text;
        await pumpScreen(t, host(c), dark: dark, scale: scale, size: size);
        expect(t.takeException(), isNull);
        expect(find.byKey(const ValueKey('otp-box-5')), findsOneWidget);
      }
      await pumpScreen(t, host(c, error: 'That code is incorrect.'),
          dark: dark, scale: scale, size: size);
      expect(find.text('That code is incorrect.'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('box count follows the configured length', (t) async {
      final c = TextEditingController();
      await pumpScreen(t, host(c, length: 4));
      expect(find.byKey(const ValueKey('otp-box-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('otp-box-4')), findsNothing);
    });

    testWidgets('typing, backspace, digits only, max length', (t) async {
      final c = TextEditingController();
      final changed = <String>[];
      final done = <String>[];
      await pumpScreen(
          t, host(c, onChanged: changed.add, onCompleted: done.add));
      await t.tap(find.byKey(const ValueKey('otp-input')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('otp-input')), '12a3');
      await t.pump();
      expect(c.text, '123'); // letters filtered
      expect(changed.last, '123');
      expect(done, isEmpty);
      // digits are painted in the boxes
      for (final d in ['1', '2', '3']) {
        expect(find.text(d), findsOneWidget);
      }
      await t.enterText(find.byKey(const ValueKey('otp-input')), '12');
      await t.pump();
      expect(c.text, '12');
      expect(find.text('3'), findsNothing);
      await t.enterText(find.byKey(const ValueKey('otp-input')), '1234567890');
      await t.pump();
      expect(c.text, '123456'); // capped at the box count
      expect(done, ['123456']);
    });

    testWidgets('paste of a full code fires onCompleted once', (t) async {
      final c = TextEditingController();
      final done = <String>[];
      await pumpScreen(t, host(c, onCompleted: done.add));
      await t.tap(find.byKey(const ValueKey('otp-input')));
      await t.pump();
      await t.enterText(find.byKey(const ValueKey('otp-input')), '482913');
      await t.pump();
      expect(done, ['482913']);
      for (final d in ['4', '8', '2', '9', '1', '3']) {
        expect(find.text(d), findsOneWidget);
      }
    });

    testWidgets('clearing the controller (wrong code) empties the boxes',
        (t) async {
      final c = TextEditingController(text: '111111');
      await pumpScreen(t, host(c));
      expect(find.text('1'), findsNWidgets(6));
      c.clear();
      await t.pump();
      expect(find.text('1'), findsNothing);
    });

    testWidgets('active box has the caret; the caret stays at the end',
        (t) async {
      final c = TextEditingController();
      await pumpScreen(t, host(c));
      await t.tap(find.byKey(const ValueKey('otp-input')));
      await t.pump();
      expect(find.byKey(const ValueKey('otp-caret')), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('otp-input')), '12');
      await t.pump();
      c.selection = const TextSelection.collapsed(offset: 0);
      await t.pump();
      expect(c.selection.baseOffset, 2);
    });
  });

  group('form parts', () {
    forEachVariant('section, choice chips, checkbox row',
        (t, dark, scale, size) async {
      var checked = false;
      await pumpScreen(
        t,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, set) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AppFormSection(
                      title: 'Transaction PIN', note: 'Optional'),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    AppChoiceChip(label: 'Cash', selected: true, onTap: () {}),
                    AppChoiceChip(
                        label: 'Wallet', selected: false, onTap: () {}),
                    AppChoiceChip(
                        label: 'A much longer option name',
                        selected: false,
                        onTap: () {}),
                  ]),
                  AppCheckboxRow(
                    value: checked,
                    onChanged: (v) => set(() => checked = v),
                    label:
                        'I agree to the terms and the privacy policy for this app.',
                  ),
                ],
              ),
            ),
          ),
        ),
        dark: dark,
        scale: scale,
        size: size,
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(AppChoiceChip).first).height,
          greaterThanOrEqualTo(44));
      expect(t.getSize(find.byType(AppCheckboxRow)).height,
          greaterThanOrEqualTo(48));
      await t.tap(find.byType(AppCheckboxRow));
      await t.pump();
      expect(checked, isTrue);
      expect(find.byIcon(AppIcons.check), findsNWidgets(2)); // chip + box
    });
  });

  group('AppAuthScaffold + pinned footer', () {
    Widget screen({bool footer = true}) => AppAuthScaffold(
          header: const AppAuthHeader.compact(
              title: 'Create your\naccount', subtitle: 'Sub'),
          body: Column(
            children: [
              const SizedBox(height: 26),
              for (var i = 0; i < 6; i++) ...[
                AppTextField(
                  key: ValueKey('field-$i'),
                  large: true,
                  label: 'Field $i',
                  prefixIcon: AppIcons.mail,
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
          footer: footer
              ? AppPinnedFooter(
                  primary: AppButton(label: 'Continue', onPressed: () {}),
                  secondary: const Text('Already have an account?'),
                )
              : null,
        );

    forEachVariant('footer is pinned and visible, no overflow',
        (t, dark, scale, size) async {
      await pumpScreen(t, screen(), dark: dark, scale: scale, size: size);
      expect(t.takeException(), isNull);
      final r = t.getRect(find.text('Continue'));
      expect(r.bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Already have an account?'), findsOneWidget);
    });

    forEachVariant('keyboard open: focused field and button both visible',
        (t, dark, scale, size) async {
      const kb = 280.0;
      await pumpScreen(t, screen(),
          dark: dark, scale: scale, size: size, keyboard: kb);
      await t.showKeyboard(find.descendant(
          of: find.byKey(const ValueKey('field-5')),
          matching: find.byType(EditableText)));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final top = size.height - kb;
      final field = t.getRect(find.byKey(const ValueKey('field-5')));
      final button = t.getRect(find.byType(AppButton));
      expect(field.bottom, lessThanOrEqualTo(button.top + 0.5),
          reason: 'focused field sits under the pinned button');
      expect(field.top, greaterThanOrEqualTo(0));
      expect(button.bottom, lessThanOrEqualTo(top + 0.5),
          reason: 'button is behind the keyboard');
      // the secondary line is hidden while typing
      expect(find.text('Already have an account?'), findsNothing);
    });

    testWidgets('fade strip sits above the button without taking taps',
        (t) async {
      var taps = 0;
      await pumpScreen(
        t,
        AppAuthScaffold(
          header: const SizedBox(height: 10),
          body: const SizedBox(height: 1200),
          footer: AppPinnedFooter(
              primary: AppButton(label: 'Go', onPressed: () => taps++)),
        ),
      );
      expect(find.byKey(const ValueKey('footer-fade')), findsOneWidget);
      await t.tap(find.text('Go'));
      expect(taps, 1);
    });

    testWidgets('caption hidden on a short screen and while typing', (t) async {
      Widget login() => const AppAuthScaffold(
            header: SizedBox(height: 10),
            body: SizedBox(height: 10),
            caption: Text("Redeemer's University"),
          );
      await pumpScreen(t, login());
      expect(find.text("Redeemer's University"), findsOneWidget);
      await pumpScreen(t, login(), size: small);
      expect(find.text("Redeemer's University"), findsNothing);
      await pumpScreen(t, login(), keyboard: 300);
      expect(find.text("Redeemer's University"), findsNothing);
    });
  });

  group('tokens', () {
    test('authAccent is the promo-orange gradient', () {
      for (final c in [AppColors.light, AppColors.dark]) {
        expect(c.authAccent.colors, [c.promoOrangeStart, c.promoOrangeEnd]);
      }
    });
  });
}
