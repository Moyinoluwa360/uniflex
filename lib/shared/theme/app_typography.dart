
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography (UI Polish 1).
///
/// **One UI font: Plus Jakarta Sans**, static 400/500/600/700 files bundled in
/// `assets/fonts/` (no runtime fetching). It was picked after checking the
/// font files themselves: it has the naira sign U+20A6 and tabular figures
/// (`tnum`); Figtree, Manrope, Switzer and Clash Display do not have `₦`.
/// Clash Display Semibold is bundled ONLY for the "Uniflex" wordmark/splash.
///
/// Rules (the pack's, and why the old headings looked wrong):
///  * No negative letter spacing except −0.01 em on 28 px+ headings.
///  * No negative word spacing anywhere. (The old headings lost the gaps
///    between words because Clash Display's space glyph is only 0.154 em and
///    every title also got −0.02 em tracking.)
///  * Money always uses tabular figures — see [tabular] / `Money`.
abstract final class AppTypography {
  static const String fontFamily = 'PlusJakartaSans';

  /// Wordmark-only family.
  static const String wordmarkFamily = 'ClashDisplay';

  // ── The named scale (colour passed in so each is theme-correct) ───────

  /// Heading 28/700.
  static TextStyle heading(AppColors c) =>
      _s(28, FontWeight.w700, c.textPrimary, height: 1.2, tracking: -0.28);

  /// Title 18/700.
  static TextStyle title(AppColors c) =>
      _s(18, FontWeight.w700, c.textPrimary, height: 1.3);

  /// Body 16/500.
  static TextStyle body(AppColors c) =>
      _s(16, FontWeight.w500, c.textPrimary, height: 1.45);

  /// Meta 14/400 textSecondary.
  static TextStyle meta(AppColors c) =>
      _s(14, FontWeight.w400, c.textSecondary, height: 1.4);

  /// Caption 12.5/400 textTertiary.
  static TextStyle caption(AppColors c) =>
      _s(12.5, FontWeight.w400, c.textTertiary, height: 1.35);

  /// Section label 13/600 textSecondary, +0.01 em.
  static TextStyle sectionLabel(AppColors c) =>
      _s(13, FontWeight.w600, c.textSecondary, tracking: 0.13);

  /// Button 16/600.
  static TextStyle button(Color color) => _s(16, FontWeight.w600, color);

  /// Small button 14/600.
  static TextStyle buttonSmall(Color color) => _s(14, FontWeight.w600, color);

  /// Nav label 11.5/600.
  static TextStyle navLabel(Color color) => _s(11.5, FontWeight.w600, color);

  /// Balance hero 40/700 (decimals use [balanceDecimals]).
  static TextStyle balanceHero(Color color) =>
      tabular(_s(40, FontWeight.w700, color, height: 1.1, tracking: -0.4));

  /// Balance decimals 22/600.
  static TextStyle balanceDecimals(Color color) =>
      tabular(_s(22, FontWeight.w600, color, height: 1.1));

  /// Greeting name 22/700.
  static TextStyle greetingName(Color color) =>
      _s(22, FontWeight.w700, color, height: 1.2);

  /// Adds tabular (fixed-width) figures to [style]. Use on every amount.
  static TextStyle tabular(TextStyle style) => style.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  // ── Material text theme, mapped from the scale ────────────────────────

  static TextTheme textTheme(AppColors c) {
    return TextTheme(
      displayLarge: _s(40, FontWeight.w700, c.textPrimary, height: 1.1, tracking: -0.4),
      displayMedium: _s(34, FontWeight.w700, c.textPrimary, height: 1.15, tracking: -0.34),
      displaySmall: _s(28, FontWeight.w700, c.textPrimary, height: 1.2, tracking: -0.28),
      headlineLarge: _s(32, FontWeight.w700, c.textPrimary, height: 1.2, tracking: -0.32),
      headlineMedium: heading(c), // Heading 28/700
      headlineSmall: _s(24, FontWeight.w700, c.textPrimary, height: 1.25),
      titleLarge: greetingName(c.textPrimary), // 22/700
      titleMedium: title(c), // Title 18/700
      titleSmall: _s(16, FontWeight.w600, c.textPrimary, height: 1.3),
      bodyLarge: body(c), // Body 16/500
      bodyMedium: body(c),
      bodySmall: meta(c), // Meta 14/400 textSecondary
      labelLarge: button(c.textPrimary), // Button 16/600
      labelMedium: sectionLabel(c), // Section label 13/600
      labelSmall: caption(c), // Caption 12.5/400 textTertiary
    );
  }

  static TextStyle _s(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
    double tracking = 0,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      // Only ≥28 px headings carry negative tracking (−0.01 em). Everything
      // else is 0 or positive. Word spacing is never touched.
      letterSpacing: tracking,
    );
  }

  /// Wordmark style — the "Uniflex" text logo (Clash Display 600, −3.5%
  /// tracking, brand green). Used by `UniflexWordmark` and the splash only.
  static TextStyle wordmark({double fontSize = 40, Color? color}) {
    return TextStyle(
      fontFamily: wordmarkFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: fontSize * -0.035,
      color: color ?? AppColors.light.brand,
    );
  }
}
