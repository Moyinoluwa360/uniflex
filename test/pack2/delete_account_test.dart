// Pack 2 — in-app account deletion (store requirement). The server rules are
// proven in supabase/pack2_account_deletion_test.sql (13 checks, rolled back).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/config/legal_links.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/profile/profile_service.dart';
import 'package:uniflex/shared/services/wallet/wallet_providers.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/student/profile/delete_account_screen.dart';

class _FakeProfile implements ProfileService {
  _FakeProfile(this.answer);
  final String answer;
  final pins = <String>[];

  @override
  Future<double> deleteMyAccount(String pin) async {
    pins.add(pin);
    throw ProfileException(deleteAccountErrorText(answer));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Future<void> _pump(WidgetTester tester, _FakeProfile fake, double balance) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      profileServiceProvider.overrideWithValue(fake),
      walletBalanceProvider.overrideWith((ref) async => balance),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const DeleteAccountScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a positive balance is shown as lost before anything happens',
      (tester) async {
    await _pump(tester, _FakeProfile('ACTIVE_ORDERS'), 1500);
    expect(find.textContaining('₦1,500 will be lost'), findsOneWidget);
    expect(find.text('Delete my account'), findsOneWidget);
  });

  testWidgets('confirm → PIN → a server refusal is shown, nothing else',
      (tester) async {
    final fake = _FakeProfile('ACTIVE_ORDERS');
    await _pump(tester, fake, 0);

    await tester.tap(find.byKey(const ValueKey('delete-account-button')));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Confirm with your PIN'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '1234');
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(fake.pins, ['1234']);
    expect(find.byKey(const ValueKey('delete-error')), findsOneWidget);
    expect(find.textContaining('still in progress'), findsWidgets);
  });

  testWidgets('"Keep my account" cancels without calling the server',
      (tester) async {
    final fake = _FakeProfile('INVALID_PIN');
    await _pump(tester, fake, 0);
    await tester.tap(find.byKey(const ValueKey('delete-account-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep my account'));
    await tester.pumpAndSettle();
    expect(fake.pins, isEmpty);
  });

  test('every refusal code has friendly text (no raw codes)', () {
    for (final code in [
      'ACTIVE_ORDERS', 'STAFF_ACCOUNT', 'INVALID_PIN', 'PIN_LOCKED',
      'PIN_NOT_SET', 'SOMETHING_NEW',
    ]) {
      final t = deleteAccountErrorText(code);
      expect(t.contains('_'), isFalse, reason: code);
      expect(t.isNotEmpty, isTrue);
    }
  });

  test('Profile links privacy, terms and account deletion; sign-up links both',
      () {
    final profile =
        File('lib/student/profile/student_profile_screen.dart').readAsStringSync();
    expect(profile.contains("ValueKey('privacy-policy-row')"), isTrue);
    expect(profile.contains("ValueKey('terms-row')"), isTrue);
    expect(profile.contains("ValueKey('delete-account-row')"), isTrue);
    final signup = File('lib/shared/auth/screens/create_account_screen.dart')
        .readAsStringSync();
    expect(signup.contains('LegalLinks.terms'), isTrue);
    expect(signup.contains('LegalLinks.privacyPolicy'), isTrue);
    expect(LegalLinks.privacyPolicy, startsWith('https://'));
    expect(LegalLinks.deleteAccount, 'https://uniflex.live/delete-account');
  });
}
