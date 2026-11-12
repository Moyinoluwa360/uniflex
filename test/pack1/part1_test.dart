// Pack 1 / Part 1 — nav gap and border, hidden balance, tap fixes.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/models/profile.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/auth/user_role.dart';
import 'package:uniflex/shared/services/profile/profile_service.dart';
import 'package:uniflex/shared/services/support/support_chat_service.dart';
import 'package:uniflex/shared/services/wallet/wallet_providers.dart';
import 'package:uniflex/shared/state/balance_visibility.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/app_spacing.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/widgets/home/home_header_parts.dart';
import 'package:uniflex/shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'package:uniflex/shared/widgets/navigation/app_glass_nav_bar.dart';
import 'package:uniflex/shared/widgets/wallet/wallet_card.dart';
import 'package:uniflex/student/profile/student_profile_screen.dart';
import 'package:uniflex/student/services/student_providers.dart';

import '../ui_polish/ui_harness.dart';

const _tabs = [
  AppNavTab(
      label: 'Home',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      screen: SizedBox()),
  AppNavTab(
      label: 'Orders',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      screen: SizedBox()),
  AppNavTab(
      label: 'Wallet',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      screen: SizedBox()),
  AppNavTab(
      label: 'Profile',
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      screen: SizedBox()),
];

Future<void> _pumpShell(WidgetTester tester,
    {required double safeBottom}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  tester.view.padding = FakeViewPadding(bottom: safeBottom * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark,
      home: const AppBottomNavShell(glass: true, tabs: _tabs),
    ),
  ));
  await tester.pump();
}

void main() {
  // ── 1.1 Nav distance from the bottom ────────────────────────────────
  group('1.1 glass nav gap', () {
    testWidgets('home-indicator phone: bar bottom is 20 pt above the screen',
        (tester) async {
      await _pumpShell(tester, safeBottom: 34);
      final r = tester.getRect(find.byKey(const ValueKey('glass-nav')));
      expect(844 - r.bottom, AppSpacing.navBottomGap);
      expect(AppSpacing.navBottomGap, 20);
      expect(r.height, 68);
      expect(r.left, 16);
      expect(390 - r.right, 16);
      // Never over the home indicator (it lives in the bottom ~13 pt).
      expect(844 - r.bottom, greaterThan(13));
    });

    testWidgets('phone without a home indicator: gap is 12', (tester) async {
      await _pumpShell(tester, safeBottom: 0);
      final r = tester.getRect(find.byKey(const ValueKey('glass-nav')));
      expect(844 - r.bottom, 12);
    });

    testWidgets('navClearanceOf = bar + gap + 12 breathing room',
        (tester) async {
      late double withIndicator;
      late double without;
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
        child: Builder(builder: (c) {
          withIndicator = AppSpacing.navClearanceOf(c);
          return const SizedBox();
        }),
      ));
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(),
        child: Builder(builder: (c) {
          without = AppSpacing.navClearanceOf(c);
          return const SizedBox();
        }),
      ));
      expect(withIndicator, 68 + 20 + 12);
      expect(without, 68 + 12 + 12);
      expect(AppSpacing.navClearance, withIndicator);
    });
  });

  // ── 1.2 Border identical on all four sides ──────────────────────────
  group('1.2 glass nav border', () {
    for (final dark in [false, true]) {
      testWidgets('edges match within tolerance (${dark ? 'dark' : 'light'})',
          (tester) async {
        const pr = 3.0;
        final key = GlobalKey();
        final c = dark ? AppColors.dark : AppColors.light;
        tester.view.physicalSize = const Size(390, 200) * pr;
        tester.view.devicePixelRatio = pr;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: c.background,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: AppGlassNavBar(
                  items: const [
                    AppGlassNavItem(label: 'Home', icon: Icons.home_outlined),
                    AppGlassNavItem(
                        label: 'Orders', icon: Icons.receipt_long_outlined),
                    AppGlassNavItem(
                        label: 'Wallet',
                        icon: Icons.account_balance_wallet_outlined),
                    AppGlassNavItem(
                        label: 'Profile', icon: Icons.person_outline),
                  ],
                  currentIndex: 0,
                  onTap: (_) {},
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        final bar = tester.getRect(find.byKey(const ValueKey('glass-nav')));
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final ByteData bytes = (await tester.runAsync<ByteData?>(() async {
          final img = await boundary.toImage(pixelRatio: pr);
          return img.toByteData(format: ui.ImageByteFormat.rawRgba);
        }))!;
        final w = (390 * pr).round();

        List<int> px(int x, int y) {
          final i = (y * w + x) * 4;
          return [
            bytes.getUint8(i),
            bytes.getUint8(i + 1),
            bytes.getUint8(i + 2),
          ];
        }

        // Average of physical pixels 1..3 in from an edge, at the middle of
        // that side (away from the rounded corners).
        List<double> band(String side) {
          final l = (bar.left * pr).round();
          final r = (bar.right * pr).round();
          final t = (bar.top * pr).round();
          final b = (bar.bottom * pr).round();
          final mx = ((l + r) / 2).round();
          final my = ((t + b) / 2).round();
          final samples = <List<int>>[];
          for (var d = 1; d <= 3; d++) {
            for (var o = -6; o <= 6; o++) {
              samples.add(switch (side) {
                'top' => px(mx + o + 60, t + d),
                'bottom' => px(mx + o + 60, b - 1 - d),
                'left' => px(l + d, my + o),
                _ => px(r - 1 - d, my + o),
              });
            }
          }
          return [
            for (var ch = 0; ch < 3; ch++)
              samples.map((s) => s[ch]).reduce((a, b) => a + b) /
                  samples.length,
          ];
        }

        final top = band('top');
        for (final side in ['bottom', 'left', 'right']) {
          final other = band(side);
          for (var ch = 0; ch < 3; ch++) {
            expect((top[ch] - other[ch]).abs(), lessThanOrEqualTo(3),
                reason: 'top vs $side, channel $ch: $top vs $other');
          }
        }
      });
    }
  });

  // ── 1.3 Hidden balance ──────────────────────────────────────────────
  group('1.3 hidden balance', () {
    setUp(BalanceVisibility.reset);
    tearDown(BalanceVisibility.reset);

    test('the hidden form is ₦ + thin space + exactly four bullets', () {
      expect(BalanceVisibility.hiddenText, '₦ ••••');
      expect(BalanceVisibility.visible.value, isFalse);
    });

    for (final amount in [0.0, 50.0, 39210.0, 1000000.0]) {
      testWidgets('₦$amount hides as exactly four dots on Home and Wallet',
          (tester) async {
        await pumpUi(
          tester,
          Column(children: [
            ColoredBox(
              color: AppColors.light.headerSolid,
              child: HeaderWalletPanel(
                  label: 'WALLET BALANCE', balance: amount, onTopUp: () {}),
            ),
            WalletCard(balance: amount, onFund: () {}),
          ]),
        );
        final hidden = find.byKey(const ValueKey('balance-hidden'));
        expect(hidden, findsNWidgets(2));
        final texts = tester
            .widgetList<RichText>(
                find.descendant(of: hidden, matching: find.byType(RichText)))
            .map((r) => r.text.toPlainText())
            .toList();
        expect(texts, [
          BalanceVisibility.hiddenText,
          BalanceVisibility.hiddenText,
        ]);
        expect(find.byKey(const ValueKey('balance-shown')), findsNothing);
      });
    }

    forEachVariant('default hidden; one toggle shows both, again hides both',
        (tester, dark, scale) async {
      final c = dark ? AppColors.dark : AppColors.light;
      await pumpUi(
        tester,
        Column(children: [
          ColoredBox(
            color: c.headerSolid,
            child: HeaderWalletPanel(
                key: const ValueKey('home'),
                label: 'WALLET BALANCE',
                balance: 1000000,
                onTopUp: () {}),
          ),
          WalletCard(
              key: const ValueKey('wallet'), balance: 1000000, onFund: () {}),
        ]),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('balance-hidden')), findsNWidgets(2));
      expect(find.bySemanticsLabel('Show balance'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Balance hidden'), findsNWidgets(2));

      final homeEye = find.descendant(
          of: find.byKey(const ValueKey('home')),
          matching: find.byKey(const ValueKey('balance-eye')));
      expect(tester.getSize(homeEye), const Size(44, 44));

      // Height reserved: the amount line does not jump when toggling.
      final hiddenH = tester
          .getSize(find.descendant(
              of: find.byKey(const ValueKey('wallet')),
              matching: find.byKey(const ValueKey('balance-hidden'))))
          .height;

      await tester.tap(homeEye);
      await tester.pump();
      expect(BalanceVisibility.visible.value, isTrue);
      expect(find.byKey(const ValueKey('balance-hidden')), findsNothing);
      expect(find.byKey(const ValueKey('balance-shown')), findsNWidgets(2));
      expect(find.bySemanticsLabel('Hide balance'), findsNWidgets(2));
      final shownH = tester
          .getSize(find.descendant(
              of: find.byKey(const ValueKey('wallet')),
              matching: find.byKey(const ValueKey('balance-shown'))))
          .height;
      expect(shownH, closeTo(hiddenH, 0.5));

      // Hide from the Wallet side: both hide.
      await tester.tap(find.descendant(
          of: find.byKey(const ValueKey('wallet')),
          matching: find.byKey(const ValueKey('balance-eye'))));
      await tester.pump();
      expect(find.byKey(const ValueKey('balance-hidden')), findsNWidgets(2));
    });

    testWidgets('loading / error states are unchanged (₦--, no eye on Home)',
        (tester) async {
      await pumpUi(
        tester,
        Column(children: [
          HeaderWalletPanel(
              label: 'WALLET BALANCE', balance: null, onTopUp: () {}),
          WalletCard(balance: null, hasError: true, onFund: () {}),
        ]),
      );
      expect(find.text('₦--'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('balance-hidden')), findsNothing);
    });

    test('the state is in memory only (never persisted or sent)', () {
      final src =
          File('lib/shared/state/balance_visibility.dart').readAsStringSync();
      for (final banned in [
        'shared_preferences',
        'SharedPreferences',
        'secure_storage',
        'supabase',
        'http',
        'hive',
      ]) {
        expect(src.contains(banned), isFalse, reason: banned);
      }
      // Reset on the student shell's create and dispose (sign-in / logout).
      final shell = File('lib/student/student_shell.dart').readAsStringSync();
      expect('BalanceVisibility.reset()'.allMatches(shell).length, 2);
    });
  });

  // ── 1.4 Tap effects ─────────────────────────────────────────────────
  group('1.4 tap effects', () {
    test('every InkWell / InkResponse outside AppTappable has a shape', () {
      final bad = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (f.path
            .replaceAll('\\', '/')
            .endsWith('shared/widgets/buttons/app_tappable.dart')) {
          continue;
        }
        final s = f.readAsStringSync();
        final re = RegExp(r'\b(InkWell|InkResponse)\(');
        for (final m in re.allMatches(s)) {
          var i = m.end;
          var depth = 1;
          while (depth > 0 && i < s.length) {
            final ch = s[i];
            if (ch == '(') depth++;
            if (ch == ')') depth--;
            i++;
          }
          final call = s.substring(m.start, i);
          if (!call.contains('borderRadius') &&
              !call.contains('customBorder')) {
            final line = '\n'.allMatches(s.substring(0, m.start)).length + 1;
            bad.add('${f.path}:$line');
          }
        }
      }
      expect(bad, isEmpty,
          reason: 'Use AppTappable or give the InkWell its shape');
    });

    test('theme: no ripple wave, soft press overlay', () {
      for (final t in [AppTheme.light, AppTheme.dark]) {
        expect(t.splashFactory, NoSplash.splashFactory);
        final c = t.extension<AppColors>()!;
        expect(t.highlightColor, c.pressOverlay);
      }
      expect(AppColors.dark.pressOverlay, const Color(0x14FFFFFF));
      expect(AppColors.light.pressOverlay, const Color(0x0F0E1210));
    });
  });

  // ── 1.4 Change Transaction PIN row ──────────────────────────────────
  group('1.4 Change Transaction PIN row', () {
    testWidgets(
        'scrolled to the bottom under the nav: first tap opens the sheet, '
        'repeat taps are ignored, and it opens again on a second visit',
        (tester) async {
      final pinCheck = _SlowProfileService();
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          currentProfileProvider.overrideWith((ref) async => const Profile(
                id: 'u1',
                role: UserRole.student,
                onboardingComplete: true,
                nickname: 'Ada',
                fullName: 'Ada Obi',
              )),
          walletBalanceProvider.overrideWith((ref) async => 1200),
          studentStatsProvider.overrideWith((ref) async => <String, dynamic>{}),
          myConversationProvider.overrideWith((ref) => Stream.value(null)),
          profileServiceProvider.overrideWithValue(pinCheck),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const AppBottomNavShell(glass: true, tabs: [
            AppNavTab(
                label: 'Profile',
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                screen: StudentProfileScreen()),
            AppNavTab(
                label: 'Other',
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                screen: SizedBox()),
          ]),
        ),
      ));
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('change-pin-row'));
      await tester.scrollUntilVisible(row, 200,
          scrollable: find.byType(Scrollable).first);
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
      await tester.pumpAndSettle();

      // The row is fully above the glass bar.
      final nav = tester.getRect(find.byKey(const ValueKey('glass-nav')));
      expect(tester.getRect(row).bottom, lessThanOrEqualTo(nav.top));

      for (var visit = 1; visit <= 2; visit++) {
        // Three quick taps while the PIN check is still in flight.
        await tester.tap(row);
        await tester.pump();
        await tester.tap(row, warnIfMissed: false);
        await tester.tap(row, warnIfMissed: false);
        await tester.pump();
        expect(pinCheck.calls, visit, reason: 'one check per visit');
        // Instant feedback while waiting.
        expect(
            find.descendant(
                of: row, matching: find.byType(CircularProgressIndicator)),
            findsOneWidget);

        pinCheck.release();
        // (The row's spinner keeps animating while the sheet is open, so
        // pump fixed frames instead of settling.)
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Save PIN'), findsOneWidget, reason: 'visit $visit');

        // Close it (back) and the row is usable again.
        Navigator.of(tester.element(find.text('Save PIN'))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Save PIN'), findsNothing);
        expect(
            find.descendant(
                of: row, matching: find.byType(CircularProgressIndicator)),
            findsNothing);
      }
    });
  });
}

class _SlowProfileService implements ProfileService {
  int calls = 0;
  Completer<bool>? _c;

  void release() => _c?.complete(true);

  @override
  Future<bool> hasTransactionPin() {
    calls++;
    _c = Completer<bool>();
    return _c!.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}
