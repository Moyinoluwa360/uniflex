import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/shared/widgets/buttons/promo_cart_button.dart';
import 'package:uniflex/shared/widgets/chips/dark_glass_chip.dart';
import 'package:uniflex/shared/widgets/home/home_header_parts.dart';
import 'package:uniflex/shared/widgets/tabs/app_segmented_tabs.dart';

import 'ui_harness.dart';

void main() {
  group('Home header pieces', () {
    forEachVariant('wallet panel, bell, avatar render without overflow',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        Container(
          color:
              dark ? AppColors.dark.headerSolid : AppColors.light.headerSolid,
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              HeaderGlassButton(
                  icon: AppIcons.bell, onTap: () {}, showDot: true),
              const SizedBox(width: 8),
              HeaderAvatar(initial: 'A', onTap: () {}),
            ]),
            const SizedBox(height: 8),
            HeaderWalletPanel(
              label: 'WALLET BALANCE',
              balance: 39210,
              onTopUp: () {},
            ),
          ]),
        ),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('₦39,210'), findsOneWidget);
      expect(find.byKey(const ValueKey('notify-dot')), findsOneWidget);
    });

    testWidgets('balance shows ₦-- while unknown and kobo only when present',
        (tester) async {
      await pumpUi(
        tester,
        HeaderWalletPanel(
            label: 'WALLET BALANCE', balance: null, onTopUp: () {}),
      );
      expect(find.text('₦--'), findsOneWidget);
      await pumpUi(
        tester,
        HeaderWalletPanel(
            label: 'WALLET BALANCE', balance: 1200.5, onTopUp: () {}),
      );
      expect(find.text('₦1,200.50'), findsOneWidget);
    });

    testWidgets('Top up is 40 high, fires once on a double tap',
        (tester) async {
      var n = 0;
      await pumpUi(
        tester,
        HeaderWalletPanel(
            label: 'WALLET BALANCE', balance: 5, onTopUp: () => n++),
      );
      expect(tester.getSize(find.byType(InkWell).last).height, 40);
      await tester.tap(find.text('Top up'));
      await tester.tap(find.text('Top up'));
      await tester.pump();
      expect(n, 1);
    });

    testWidgets('the bell shows a dot only when asked, never a count',
        (tester) async {
      await pumpUi(
          tester, HeaderGlassButton(icon: AppIcons.bell, onTap: () {}));
      expect(find.byKey(const ValueKey('notify-dot')), findsNothing);
      await pumpUi(tester,
          HeaderGlassButton(icon: AppIcons.bell, onTap: () {}, showDot: true));
      final dot = tester.getSize(find.byKey(const ValueKey('notify-dot')));
      expect(dot, const Size(10, 10));
      expect(find.byType(Text), findsNothing);
    });
  });

  group('Home mode toggle (AppSegmentedTabs)', () {
    forEachVariant('two labels, full width', (tester, dark, scale) async {
      var i = 0;
      await pumpUi(
        tester,
        StatefulBuilder(
          builder: (context, set) => AppSegmentedTabs(
            labels: const ['Food Delivery', 'Errand'],
            index: i,
            onChanged: (v) => set(() => i = v),
          ),
        ),
        dark: dark,
        textScale: scale,
      );
      await tester.tap(find.text('Errand'));
      await tester.pumpAndSettle();
      expect(i, 1);
    });
  });

  group('Major chip + cart button', () {
    forEachVariant('render', (tester, dark, scale) async {
      await pumpUi(
        tester,
        const Column(children: [
          DarkGlassChip('MAJOR'),
          SizedBox(height: 8),
          PromoCartButton(count: 12, onTap: _noop),
        ]),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('MAJOR'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
    });

    testWidgets('cart button is 60x60 and taps once', (tester) async {
      var n = 0;
      await pumpUi(tester, PromoCartButton(count: 2, onTap: () => n++));
      expect(tester.getSize(find.byType(PromoCartButton)), const Size(60, 60));
      await tester.tap(find.byType(PromoCartButton));
      await tester.tap(find.byType(PromoCartButton));
      await tester.pump();
      expect(n, 1);
    });
  });
}

void _noop() {}
