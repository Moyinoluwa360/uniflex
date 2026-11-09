import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/widgets/image_upload/image_upload_field.dart';

import 'ui_harness.dart';

void main() {
  group('chart palette tokens', () {
    for (final entry
        in {'light': AppColors.light, 'dark': AppColors.dark}.entries) {
      test('${entry.key}: fees/food are distinct and never the promo orange',
          () {
        final c = entry.value;
        expect(c.chartFees, isNot(equals(c.chartFood)));
        expect(c.chartPalette.length, greaterThanOrEqualTo(4));
        expect(c.chartPalette.toSet().length, c.chartPalette.length);
        expect(c.chartPalette.contains(c.promoOrangeStart), isFalse);
      });
    }
  });

  group('ImageUploadField', () {
    forEachVariant('renders the picker with an empty value',
        (tester, dark, scale) async {
      await pumpUi(
        tester,
        ImageUploadField(uploadFn: (_, __) async => 'https://x/y.png'),
        dark: dark,
        textScale: scale,
      );
      expect(find.text('Choose photo'), findsOneWidget);
      expect(find.text('Tap to add photo'), findsOneWidget);
    });
  });
}
