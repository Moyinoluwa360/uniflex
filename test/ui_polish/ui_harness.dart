import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_theme.dart';

/// Pumps [child] in the real [AppTheme] (light or dark) at a given text scale
/// on a phone-sized surface. Any RenderFlex overflow throws and fails the
/// test, which is the "no overflow" check.
Future<void> pumpUi(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  double textScale = 1.0,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: w!,
      ),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Runs [body] for light/dark × 1.0/1.3.
void forEachVariant(
  String name,
  Future<void> Function(WidgetTester tester, bool dark, double scale) body,
) {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('$name (${dark ? 'dark' : 'light'}, x$scale)',
          (tester) async {
        await body(tester, dark, scale);
      });
    }
  }
}
