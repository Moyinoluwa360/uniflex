import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/state/balance_visibility.dart';
import 'package:uniflex/shared/widgets/cart/cart_widgets.dart';
import 'package:uniflex/shared/widgets/chat/support_order_chip.dart';
import 'package:uniflex/shared/widgets/tier/tier_header.dart';
import 'package:uniflex/shared/widgets/tracking/pin_digit_boxes.dart';
import 'package:uniflex/shared/widgets/wallet/transaction_row.dart';
import 'package:uniflex/shared/widgets/wallet/wallet_card.dart';

import 'ui_harness.dart';

void main() {
  group('WalletCard', () {
    setUp(() => BalanceVisibility.visible.value = true);
    tearDown(BalanceVisibility.reset);
    forEachVariant('shows balance, Fund Wallet and the account number',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        WalletCard(
          balance: 12500.5,
          onFund: () {},
          accountTitle: 'Wema Bank · Uniflex Student',
          accountValue: '1234567890',
          onCopyAccount: () {},
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('balance-shown')), findsOneWidget);
      expect(find.text('Fund Wallet'), findsOneWidget);
      expect(find.text('1234567890'), findsOneWidget);
    });

    testWidgets('the eye hides the balance but keeps the account number',
        (tester) async {
      await pumpUi(
        tester,
        WalletCard(
          balance: 3000,
          onFund: () {},
          accountTitle: 'Wema Bank',
          accountValue: '1234567890',
          onCopyAccount: () {},
        ),
      );
      await tester.tap(find.byKey(const ValueKey('balance-eye')));
      await tester.pump();
      expect(find.byKey(const ValueKey('balance-hidden')), findsOneWidget);
      expect(find.byKey(const ValueKey('balance-shown')), findsNothing);
      expect(find.text('1234567890'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('balance-eye')));
      await tester.pump();
      expect(find.byKey(const ValueKey('balance-shown')), findsOneWidget);
    });

    testWidgets('Fund Wallet fires onFund', (tester) async {
      var funded = 0;
      await pumpUi(tester, WalletCard(balance: 0, onFund: () => funded++));
      await tester.tap(find.text('Fund Wallet'));
      expect(funded, 1);
    });
  });

  group('TransactionRow', () {
    forEachVariant('spending uses a real minus, credit uses +',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        const Column(children: [
          TransactionRow(
            title: 'Order payment',
            dateText: '9 Nov, 14:02',
            amount: 1500,
            isCredit: false,
            balanceAfter: 8500,
          ),
          TransactionRow(
            title: 'Wallet funding',
            dateText: '9 Nov, 13:00',
            amount: 10000,
            isCredit: true,
            balanceAfter: 10000,
          ),
        ]),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('−₦1,500'), findsOneWidget);
      expect(find.text('+₦10,000'), findsOneWidget);
      expect(find.text('Bal: ₦8,500'), findsOneWidget);
    });
  });

  group('PinDigitBoxes', () {
    forEachVariant('one box per digit', (tester, dark, scale) async {
      await pumpUi(tester, const PinDigitBoxes(pin: '4821'),
          dark: dark, textScale: scale);
      for (final d in ['4', '8', '2', '1']) {
        expect(find.text(d), findsOneWidget);
      }
    });
  });

  group('TierHeader', () {
    for (final tier in [null, 'Bronze', 'Silver', 'Gold', 'Platinum']) {
      forEachVariant('tier $tier, with and without nickname',
          (tester, dark, scale) async {
        await pumpUi(
          tester,
          Column(children: [
            TierHeader(
                tier: tier, name: 'Ada Obi', nickname: 'ada', initial: 'A'),
            TierHeader(tier: tier, name: 'Bola', initial: 'B'),
          ]),
          dark: dark,
          textScale: scale,
        );
        expect(find.text('Ada Obi'), findsOneWidget);
        expect(find.text('@ada'), findsOneWidget);
        expect(find.text('Bola'), findsOneWidget);
        expect(find.textContaining('@'), findsOneWidget);
      });
    }
  });

  group('QuantityStepper / AddItemButton', () {
    testWidgets('a null callback disables that side', (tester) async {
      var plus = 0;
      var minus = 0;
      await pumpUi(
        tester,
        QuantityStepper(quantity: 1, onMinus: null, onPlus: () => plus++),
      );
      await tester.tap(find.byKey(const ValueKey('step-minus')));
      await tester.tap(find.byKey(const ValueKey('step-plus')));
      expect(minus, 0);
      expect(plus, 1);
    });

    forEachVariant('add button is 36x36 and tappable',
        (tester, dark, scale) async {
      var taps = 0;
      await pumpUi(tester, AddItemButton(onTap: () => taps++),
          dark: dark, textScale: scale);
      expect(tester.getSize(find.byType(AddItemButton)), const Size(36, 36));
      await tester.tap(find.byType(AddItemButton));
      expect(taps, 1);
    });

    testWidgets('disabled add button ignores taps', (tester) async {
      await pumpUi(tester, const AddItemButton(onTap: null));
      await tester.tap(find.byType(AddItemButton));
    });
  });

  group('SupportOrderChip', () {
    forEachVariant('defaults to a readable foreground and shows the id',
        (tester, dark, scale) async {
      await pumpUi(tester, const SupportOrderChip(refId: 'abcdef1234'),
          dark: dark, textScale: scale);
      expect(find.text('Order #ABCDEF12'), findsOneWidget);
    });
  });
}
