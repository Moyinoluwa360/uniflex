// Small Fix Pack, Fix 2: Drinks / Items / Others sections and item lines in
// the shared order breakdown are large enough to read (labels + lines >= 16,
// notes/amounts >= 14), wrap instead of cutting off, and keep data order.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_models.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_widget.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/app_theme.dart';

const _long1 =
    'Jollof rice with fried plantain, two pieces of grilled chicken and extra pepper sauce';
const _long2 =
    'Chilled zobo drink with ginger, pineapple and cloves, large bottle';

Map<String, dynamic> _l(String n, int q, num u) =>
    {'name': n, 'quantity': q, 'unit_price': u, 'line_total': q * u};

OrderBreakdownData _data() => OrderBreakdownData.fromJson({
      'order_id': 'o',
      'kind': 'delivery',
      'vendors': [
        {
          'vendor_id': 'v',
          'vendor_name': 'Mama Put',
          'vendor_location': 'Behind the main gate',
          'packs': [
            {
              'index': 1,
              'price': 1500,
              'items': [
                {'name': _long1, 'quantity': 2},
              ],
            },
          ],
          'items': [_l('Meat pie', 3, 500), _l(_long1, 1, 2500)],
          'drinks': [_l('Water', 12, 200), _l(_long2, 2, 800)],
          'others': [_l('Nylon bag', 1, 50)],
          'item_count': 8,
          'vendor_total': 9000,
        },
      ],
    });

Widget _host(ThemeData theme, double scale) => MaterialApp(
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
            size: const Size(390, 844), textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: OrderBreakdownView(data: _data()),
            ),
          ),
        ),
      ),
    );

double _size(WidgetTester t, Finder f) {
  final w = t.widget<Text>(f.first);
  return w.style!.fontSize!;
}

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      final name = '${dark ? 'dark' : 'light'} x$scale';
      testWidgets('breakdown sections readable — $name', (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final theme = dark ? AppTheme.dark : AppTheme.light;
        final c = dark ? AppColors.dark : AppColors.light;
        await tester.pumpWidget(_host(theme, scale));
        // Open the pack so its lines render too.
        await tester.tap(find.textContaining('Pack 1'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        // Labels: 16, bold, textPrimary — in data order.
        final labels = ['Items', 'Drinks', 'Others'];
        for (final l in labels) {
          final f = find.byKey(ValueKey('section-label-$l'));
          expect(f, findsOneWidget);
          final s = tester.widget<Text>(f).style!;
          expect(s.fontSize, greaterThanOrEqualTo(16));
          expect(s.fontWeight, FontWeight.w700);
          expect(s.color, c.textPrimary);
        }
        final ys = [
          for (final l in labels)
            tester.getTopLeft(find.byKey(ValueKey('section-label-$l'))).dy
        ];
        expect(ys, [...ys]..sort());

        // Hairline dividers between sections (items/drinks/others follow a pack).
        for (final l in labels) {
          expect(find.byKey(ValueKey('section-divider-$l')), findsOneWidget);
        }

        // Item lines: >= 16, quantity bold, names wrap (full text, no ellipsis
        // within 3 lines at these widths), and order is preserved.
        final rich = find.byWidgetPredicate(
            (w) => w is Text && w.textSpan != null && w.maxLines == 3);
        expect(rich, findsWidgets);
        for (final e in tester.widgetList<Text>(rich)) {
          expect(e.style!.fontSize, greaterThanOrEqualTo(16));
          expect(e.style!.color, c.textPrimary);
          final qty = (e.textSpan! as TextSpan).children!.first as TextSpan;
          expect(qty.style!.fontWeight, FontWeight.w700);
          expect(qty.style!.fontSize, greaterThanOrEqualTo(16));
          expect(qty.style!.fontFeatures, isNotEmpty);
        }
        expect(
            find.textContaining('Water', findRichText: true), findsOneWidget);
        final order = [
          'Meat pie',
          'Water',
          'Chilled zobo',
          'Nylon bag',
        ];
        final tops = [
          for (final n in order)
            tester
                .getTopLeft(find.byWidgetPredicate((w) =>
                    w is Text &&
                    w.textSpan != null &&
                    w.textSpan!.toPlainText().contains(n)))
                .dy
        ];
        expect(tops, [...tops]..sort());

        // Amounts are secondary and >= 14.
        expect(_size(tester, find.text('₦1500')), greaterThanOrEqualTo(14));
        // Drinks weigh the same as food items.
        double lineSize(String n) => tester
            .widgetList<Text>(rich)
            .firstWhere((t) => t.textSpan!.toPlainText().contains(n))
            .style!
            .fontSize!;
        expect(lineSize('Water'), lineSize('Meat pie'));

        // Nothing overflows the 390 px width.
        for (final e in tester.widgetList<Text>(rich)) {
          expect(e.maxLines, 3);
        }
        final box = tester.getRect(find.byType(OrderBreakdownView));
        expect(box.right, lessThanOrEqualTo(390));
      });
    }
  }
}
