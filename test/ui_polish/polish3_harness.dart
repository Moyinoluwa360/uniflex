// Shared helpers for the UI Polish 3 tests.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/widgets/auth/app_auth_header.dart';

/// The real fonts, so text widths are realistic (tests default to a box font).
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final e in {
    'PlusJakartaSans': [
      'PlusJakartaSans-Regular.ttf',
      'PlusJakartaSans-Medium.ttf',
      'PlusJakartaSans-SemiBold.ttf',
      'PlusJakartaSans-Bold.ttf',
    ],
    'ClashDisplay': ['ClashDisplay-Semibold.ttf'],
  }.entries) {
    final l = FontLoader(e.key);
    for (final f in e.value) {
      l.addFont(Future.value(
          ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }
}

const small = Size(320, 568);
const normal = Size(390, 844);

Future<void> pumpScreen(
  WidgetTester t,
  Widget home, {
  bool dark = false,
  double scale = 1.0,
  Size size = normal,
  double keyboard = 0,
  Widget Function(Widget app)? wrap,
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard * 2);
  addTearDown(t.view.reset);
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, w) => MediaQuery(
      data:
          MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
      child: w!,
    ),
    home: home,
  );
  await t.pumpWidget(wrap == null ? app : wrap(app));
  await t.pump();
}

void forEachVariant(
  String name,
  Future<void> Function(WidgetTester t, bool dark, double scale, Size size)
      body,
) {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      for (final size in [small, normal]) {
        testWidgets(
            '$name (${dark ? 'dark' : 'light'}, x$scale, ${size.width.toInt()}x${size.height.toInt()})',
            (t) => body(t, dark, scale, size));
      }
    }
  }
}

Rect orangeRect(Size size, bool compact) {
  final reach = AppAuthHeader.accentReach(compact);
  final depth = AppAuthHeader.accentDepth(compact);
  return Rect.fromLTRB(size.width - reach, 0, size.width, depth);
}
