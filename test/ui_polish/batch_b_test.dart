import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/widgets/cards/order_summary_card.dart';
import 'package:uniflex/shared/widgets/cart/cart_widgets.dart';
import 'package:uniflex/shared/widgets/cart/summary_row.dart';
import 'package:uniflex/shared/widgets/lists/app_list_group.dart';
import 'package:uniflex/shared/widgets/lists/notification_row.dart';
import 'package:uniflex/shared/widgets/status/app_status_label.dart';
import 'package:uniflex/shared/widgets/tracking/tracking_stepper.dart';

import 'ui_harness.dart';

void main() {
  group('OrderSummaryCard', () {
    forEachVariant('renders with Cancel + Track, no overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        OrderSummaryCard(
          statusText: 'Finding a rider',
          statusTone: StatusTone.waiting,
          shortId: '#A1B2C3',
          title: 'Food Delivery',
          metaLines: const ['Elijah Hall, Block C, Room 204, Long Road'],
          amountText: '₦1,500 fee',
          onCancel: () {},
          onTrack: () {},
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('Finding a rider'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Track'), findsOneWidget);
    });

    testWidgets('Cancel is quietDanger and is absent when not allowed',
        (tester) async {
      await pumpUi(
        tester,
        OrderSummaryCard(
          statusText: 'Order Placed',
          statusTone: StatusTone.waiting,
          shortId: '#1',
          title: 'Food Delivery',
          onCancel: () {},
          onTrack: () {},
        ),
      );
      final cancel =
          tester.widget<AppButton>(find.byKey(const ValueKey('order-cancel')));
      expect(cancel.variant, AppButtonVariant.quietDanger);
      final track =
          tester.widget<AppButton>(find.byKey(const ValueKey('order-track')));
      expect(track.variant, AppButtonVariant.secondary);

      await pumpUi(
        tester,
        const OrderSummaryCard(
          statusText: 'Out for Delivery',
          statusTone: StatusTone.live,
          shortId: '#1',
          title: 'Food Delivery',
          onTrack: null,
        ),
      );
      expect(find.byKey(const ValueKey('order-cancel')), findsNothing);
      expect(find.byKey(const ValueKey('order-track')), findsNothing);
    });

    testWidgets('Cancel and Track each fire once', (tester) async {
      var cancels = 0, tracks = 0;
      await pumpUi(
        tester,
        OrderSummaryCard(
          statusText: 'Order Placed',
          statusTone: StatusTone.waiting,
          shortId: '#1',
          title: 'Food Delivery',
          onCancel: () => cancels++,
          onTrack: () => tracks++,
        ),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.tap(find.text('Track'));
      await tester.pump();
      expect(cancels, 1);
      expect(tracks, 1);
    });
  });

  group('Cart widgets', () {
    forEachVariant('cart item row with stepper + remove, no overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        CartItemRow(
          title: 'Jollof rice with chicken and plantain',
          options: 'Extra pepper, no onions',
          unitLine: '₦1,500 each',
          quantity: 2,
          onMinus: () {},
          onPlus: () {},
          onRemove: () {},
          lineTotal: 3000,
          leading: const SizedBox(width: 48, height: 48),
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('₦3,000'), findsOneWidget);
    });

    testWidgets('stepper callbacks fire once per tap', (tester) async {
      var minus = 0, plus = 0;
      await pumpUi(
        tester,
        QuantityStepper(
            quantity: 3, onMinus: () => minus++, onPlus: () => plus++),
      );
      await tester.tap(find.byKey(const ValueKey('step-minus')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('step-plus')));
      await tester.pump();
      expect(minus, 1);
      expect(plus, 1);
      expect(
          tester.getSize(find.byKey(const ValueKey('step-minus'))).height, 32);
    });

    testWidgets('no stepper when callbacks are missing (Orders > Cart tab)',
        (tester) async {
      await pumpUi(
        tester,
        const CartItemRow(title: '2× Rice', lineTotal: 2400),
      );
      expect(find.byKey(const ValueKey('step-plus')), findsNothing);
    });

    forEachVariant('totals and summary rows', (tester, dark, scale) async {
      await pumpUi(
        tester,
        const Column(children: [
          CartTotalRow(label: 'Subtotal', amount: 12300, strong: true),
          CartTotalRow(label: 'Pack fees', amount: 300),
          SummaryRow(label: 'Food + packs', value: '₦12,600'),
          SummaryRow(label: 'Delivery fees', value: '₦1,500', bold: true),
        ]),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('₦12,300'), findsOneWidget);
      expect(find.text('₦1,500'), findsOneWidget);
    });
  });

  group('NotificationRow', () {
    forEachVariant('unread and read in a list group',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        AppListGroup(children: [
          NotificationRow(
            icon: Icons.local_shipping_outlined,
            title: 'Your rider is on the way and will arrive in a few minutes',
            body: 'Order #A1B2C3 is out for delivery.',
            timeText: 'Just now',
            unread: true,
            onTap: () {},
          ),
          const NotificationRow(
            icon: Icons.chat_bubble_outline,
            title: 'Message from support',
            body: 'We have looked into it.',
            timeText: 'Yesterday',
            unread: false,
          ),
        ]),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('unread-dot')), findsOneWidget);
    });
  });

  group('TrackingStepper', () {
    forEachVariant('done / current / upcoming', (tester, dark, scale) async {
      await pumpUi(
        tester,
        const TrackingStepper(
          labels: [
            'Order Placed',
            'Being Sourced — Rider is sourcing your items',
            'Awaiting Final Payment',
            'Out for Delivery',
          ],
          states: [
            TrackingStepState.done,
            TrackingStepState.current,
            TrackingStepState.upcoming,
            TrackingStepState.upcoming,
          ],
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.byKey(const ValueKey('step-done-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('step-current-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('step-upcoming-2')), findsOneWidget);
    });
  });
}
