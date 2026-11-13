// Paystack: "Dedicated NUBAN is not available for your business". The
// Wallet shows no bank-transfer / virtual-account section at all until it is.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/widgets/wallet/wallet_card.dart';

import '../ui_polish/ui_harness.dart';

void main() {
  testWidgets('WalletCard without account data draws no account strip',
      (tester) async {
    await pumpUi(tester, WalletCard(balance: 500, onFund: () {}));
    expect(find.byKey(const ValueKey('account-strip')), findsNothing);
    expect(find.textContaining('Virtual'), findsNothing);
    expect(find.byType(Divider), findsNothing);
    expect(find.text('Fund Wallet'), findsOneWidget);
  });

  test('Wallet screen neither requests nor shows a virtual account', () {
    final src =
        File('lib/student/wallet/wallet_screen.dart').readAsStringSync();
    expect(src.contains('createVirtualAccount'), isFalse);
    expect(src.contains('accountTitle'), isFalse);
    expect(src.contains('Pending Activation'), isFalse);
    expect(src.contains('Awaiting Paystack'), isFalse);
  });
}
