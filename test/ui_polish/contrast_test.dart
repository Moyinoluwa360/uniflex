import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/app_colors.dart';
import 'package:uniflex/shared/theme/tier_tokens.dart';

/// WCAG 2.x contrast for the token pairs, in BOTH themes.

double _lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _lum(Color c) =>
    0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b);

/// [top] painted over the opaque [bottom].
Color _over(Color top, Color bottom) {
  final a = top.a;
  return Color.from(
    alpha: 1,
    red: top.r * a + bottom.r * (1 - a),
    green: top.g * a + bottom.g * (1 - a),
    blue: top.b * a + bottom.b * (1 - a),
  );
}

double ratio(Color fg, Color bg) {
  final f = fg.a < 1 ? _over(fg, bg) : fg;
  final l1 = _lum(f), l2 = _lum(bg);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final sets = {'light': AppColors.light, 'dark': AppColors.dark};

  for (final entry in sets.entries) {
    final name = entry.key;
    final c = entry.value;

    group('contrast ($name)', () {
      void check(String what, Color fg, Color bg, [double min = 4.5]) {
        final r = ratio(fg, bg);
        // ignore: avoid_print
        print('  [$name] ${what.padRight(44)} ${r.toStringAsFixed(2)}'
            '${r < min ? '   <-- FAILS (min $min)' : ''}');
        expect(r, greaterThanOrEqualTo(min), reason: '$name: $what = $r');
      }

      test('primary + secondary text on background / surface / surfaceRaised', () {
        for (final bg in {
          'background': c.background,
          'surface': c.surface,
          'surfaceRaised': c.surfaceRaised,
        }.entries) {
          check('textPrimary on ${bg.key}', c.textPrimary, bg.value);
          check('textSecondary on ${bg.key}', c.textSecondary, bg.value);
        }
      });

      test('textTertiary on surface', () {
        check('textTertiary on surface', c.textTertiary, c.surface);
      });

      test('textTertiary on background / surfaceRaised (informational)', () {
        // The pack only requires surface; report the others without failing.
        for (final bg in {'background': c.background, 'surfaceRaised': c.surfaceRaised}.entries) {
          final r = ratio(c.textTertiary, bg.value);
          // ignore: avoid_print
          print('  [$name] textTertiary on ${bg.key} (info)'.padRight(52) +
              r.toStringAsFixed(2));
        }
      });

      test('brand pairs', () {
        check('onBrand on brand', c.onBrand, c.brand);
        check('brandText on surface', c.brandText, c.surface);
        check('brandText on background', c.brandText, c.background);
      });

      test('danger pairs', () {
        check('dangerText on surface', c.dangerText, c.surface);
        check('dangerText on surfaceRaised', c.dangerText, c.surfaceRaised);
        check('white on dangerSolid', c.onDangerSolid, c.dangerSolid);
      });

      test('nav text on the glass bar over the page background', () {
        final glass = _over(c.glassFill, c.background);
        check('inactive nav text (textSecondary) on glass', c.textSecondary, glass);
        final capsule = _over(c.navCapsule, glass);
        check('active nav text on capsule', c.onNavCapsule, capsule);
      });

      test('promo / badge: white on cart badge and promo orange', () {
        check('white on cart badge', c.onDangerSolid, c.promoOrangeBadge);
        // Informational: the pack does not list the cart-button label pair.
        for (final e in {
          'white on promoOrangeButton': (c.onDangerSolid, c.promoOrangeButton),
          'white on promoOrange gradient end': (c.onDangerSolid, c.promoOrangeEnd),
          'onBrand on promoOrangeButton': (c.onBrand, c.promoOrangeButton),
        }.entries) {
          final r = ratio(e.value.$1, e.value.$2);
          // ignore: avoid_print
          print('  [$name] ${e.key} (info)'.padRight(52) + r.toStringAsFixed(2));
        }
      });

      test('tier text on its own wash', () {
        final brightness = c.isDark ? Brightness.dark : Brightness.light;
        for (final t in TierTokens.known) {
          final s = TierTokens.of(t, brightness)!;
          final wash = _over(s.washStart, c.surface);
          check('$t text on wash', s.text, wash);
        }
      });
    });
  }
}
