// Switches: the theme paints a white thumb on a brand-green track when on.
// Per-screen colour overrides made the thumb green-on-green (looked like a
// solid green pill). No screen may override switch colours.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_theme.dart';

void main() {
  test('no screen overrides switch thumb/track colours', () {
    final offenders = <String>[];
    final pattern = RegExp(
        r'\b(activeThumbColor|activeColor|activeTrackColor|inactiveThumbColor|thumbColor|trackColor)\s*:');
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.replaceAll('\\', '/').endsWith('shared/theme/app_theme.dart')) {
        continue;
      }
      final src = f.readAsStringSync();
      if (src.contains('Switch') && pattern.hasMatch(src)) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });

  test('theme: on = white thumb on a different-coloured track', () {
    final t = AppTheme.light.switchTheme;
    const on = {WidgetState.selected};
    final thumb = t.thumbColor!.resolve(on);
    final track = t.trackColor!.resolve(on);
    expect(thumb, const Color(0xFFFFFFFF));
    expect(track, isNot(thumb));
  });
}
