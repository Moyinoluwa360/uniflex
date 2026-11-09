import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/models/delivery_group.dart';
import 'package:uniflex/shared/models/order.dart';
import 'package:uniflex/shared/theme/tier_tokens.dart';
import 'package:uniflex/shared/widgets/format/money.dart';
import 'package:uniflex/shared/widgets/status/app_status_label.dart';
import 'package:uniflex/shared/widgets/status/status_presentation.dart';

import 'ui_harness.dart';

void main() {
  group('Money', () {
    test('whole naira has commas and no decimals', () {
      expect(Money.format(39210), '₦39,210');
      expect(Money.format(0), '₦0');
      expect(Money.format(500), '₦500');
      expect(Money.format(1234567), '₦1,234,567');
      expect(Money.format(39210.0), '₦39,210');
    });

    test('kobo are shown only when present', () {
      expect(Money.format(39210.5), '₦39,210.50');
      expect(Money.format(99.05), '₦99.05');
      expect(Money.format(0.99), '₦0.99');
    });

    test('hero always shows two decimals', () {
      expect(Money.hero(39210), '₦39,210.00');
      expect(Money.hero(39210.5), '₦39,210.50');
      final p = Money.heroParts(39210);
      expect(p.whole, '₦39,210');
      expect(p.decimals, '.00');
    });

    test('signed forms use a real minus sign (U+2212)', () {
      expect(Money.minus(2000), '−₦2,000');
      expect(Money.minus(2000).codeUnitAt(0), 0x2212);
      expect(Money.plus(10000), '+₦10,000');
      expect(Money.signed(-2000), '−₦2,000');
      expect(Money.signed(10000), '+₦10,000');
      expect(Money.signed(0), '₦0');
      expect(Money.minus(-2000), '−₦2,000'); // magnitude, never double sign
    });

    test('negative amounts format with the real minus', () {
      expect(Money.format(-2000), '−₦2,000');
      expect(Money.hero(-2000.5), '−₦2,000.50');
    });

    test('never changes the amount (rounds only to kobo)', () {
      expect(Money.format(10.004), '₦10');
      expect(Money.format(10.006), '₦10.01');
    });

    testWidgets('MoneyText uses tabular figures; positive is brandText',
        (tester) async {
      await pumpUi(
        tester,
        const Column(children: [
          MoneyText(1250),
          MoneyText(1250, tone: MoneyTone.positive, signed: true),
        ]),
      );
      final a = tester.widget<Text>(find.text('₦1,250'));
      expect(
          a.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(find.text('+₦1,250'), findsOneWidget);
    });

    testWidgets('MoneyHero renders whole + smaller decimals', (tester) async {
      await pumpUi(tester, const MoneyHero(39210));
      expect(
          find.textContaining('₦39,210', findRichText: true), findsOneWidget);
    });
  });

  group('Status presentation', () {
    test('every OrderStatus value has a label and a tone', () {
      for (final s in OrderStatus.values) {
        final got = StatusPresenter.order(s);
        expect(got.label, isNotEmpty, reason: s.name);
        // Existing label kept for every order status.
        expect(got.label, s.label, reason: s.name);
      }
    });

    test('every DeliveryGroupStatus value is covered; labels kept except pool',
        () {
      for (final s in DeliveryGroupStatus.values) {
        final got = StatusPresenter.group(s);
        if (s == DeliveryGroupStatus.commitmentPaid) {
          expect(got.label, 'Finding a rider');
        } else {
          expect(got.label, s.label, reason: s.name);
        }
      }
    });

    test('tones follow the spec', () {
      StatusTone g(DeliveryGroupStatus s) => StatusPresenter.group(s).tone;
      expect(g(DeliveryGroupStatus.placed), StatusTone.waiting);
      expect(g(DeliveryGroupStatus.commitmentPaid), StatusTone.waiting);
      expect(g(DeliveryGroupStatus.awaitingFinalPayment), StatusTone.waiting);
      expect(g(DeliveryGroupStatus.riderAccepted), StatusTone.live);
      expect(g(DeliveryGroupStatus.outForDelivery), StatusTone.live);
      expect(g(DeliveryGroupStatus.completed), StatusTone.done);
      expect(g(DeliveryGroupStatus.cancelled), StatusTone.cancelled);

      StatusTone o(OrderStatus s) => StatusPresenter.order(s).tone;
      expect(o(OrderStatus.placed), StatusTone.waiting);
      expect(o(OrderStatus.preparing), StatusTone.live);
      expect(o(OrderStatus.outForDelivery), StatusTone.live);
      expect(o(OrderStatus.completed), StatusTone.done);
      expect(o(OrderStatus.cancelled), StatusTone.cancelled);
    });

    test('errand wording is kept', () {
      expect(StatusPresenter.order(OrderStatus.placed, isErrand: true).label,
          'Errand placed');
      expect(
          StatusPresenter.order(OrderStatus.beingSourced, isErrand: true).label,
          'Rider assigned');
      expect(
          StatusPresenter.order(OrderStatus.outForDelivery, isErrand: true)
              .label,
          'On the way');
      expect(
          StatusPresenter.order(OrderStatus.beingSourced, isErrand: true).tone,
          StatusTone.live);
    });

    test('gift statuses', () {
      expect(StatusPresenter.gift('preparing').label, 'Being prepared');
      expect(StatusPresenter.gift('on_the_way').label, 'On its way');
      expect(StatusPresenter.gift('delivered').tone, StatusTone.done);
      expect(StatusPresenter.gift('cancelled').tone, StatusTone.cancelled);
      expect(StatusPresenter.gift('???').label, 'Order placed');
    });

    test('every raw database status string maps to something', () {
      const raws = [
        // orders
        'placed', 'preparing', 'ready', 'out_for_delivery', 'ready_for_pickup',
        'completed', 'cancelled', 'being_sourced', 'awaiting_final_payment',
        // delivery groups
        'commitment_paid', 'rider_accepted',
      ];
      for (final r in raws) {
        expect(StatusPresenter.raw(r).label, isNotEmpty, reason: r);
      }
      expect(StatusPresenter.raw('commitment_paid').label, 'Finding a rider');
      expect(StatusPresenter.raw('rider_accepted').tone, StatusTone.live);
      // Unknown falls back like the models do.
      expect(StatusPresenter.raw('wat').label, 'Order Placed');
    });

    test('no label still says "In Rider Pool"', () {
      for (final s in DeliveryGroupStatus.values) {
        expect(StatusPresenter.group(s).label, isNot('In Rider Pool'));
      }
    });
  });

  group('Tier tokens', () {
    test('known tiers resolve in both themes, case-insensitively', () {
      for (final t in TierTokens.known) {
        for (final b in Brightness.values) {
          expect(TierTokens.of(t, b), isNotNull, reason: '$t $b');
          expect(TierTokens.of(t.toUpperCase(), b), isNotNull);
        }
      }
    });

    test('unknown / missing / blank tier falls back to null (plain surface)',
        () {
      expect(TierTokens.of(null, Brightness.light), isNull);
      expect(TierTokens.of('', Brightness.dark), isNull);
      expect(TierTokens.of('Mythic', Brightness.dark), isNull);
    });

    test('spec values for Bronze / Silver / Platinum', () {
      final b = TierTokens.of('Bronze', Brightness.light)!;
      expect(b.ring, const Color(0xFFB87333));
      expect(b.text, const Color(0xFF8A4F1D));
      final s = TierTokens.of('Silver', Brightness.dark)!;
      expect(s.ring, const Color(0xFFB7C0C9));
      final p = TierTokens.of('Platinum', Brightness.dark)!;
      expect(p.text, const Color(0xFFC3C9F5));
    });
  });
}
