import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography scale. Inter is used across the app for the clean,
/// high-legibility feel of Notion/Linear/Airbnb-tier products — one
/// typeface, driven entirely by weight and size rather than mixing fonts.
///
/// Built on Material's type scale (display/headline/title/body/label) so it
/// plugs directly into [ThemeData.textTheme] and every built-in widget picks
/// it up automatically.
abstract final class AppTypography {
  static TextTheme textTheme(Color baseColor) {
    final base = GoogleFonts.interTextTheme();
    return base
        .copyWith(
          displayLarge: base.displayLarge?.copyWith(
            fontSize: 40,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.15,
          ),
          displayMedium: base.displayMedium?.copyWith(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.2,
          ),
          headlineLarge: base.headlineLarge?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          titleSmall: base.titleSmall?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: base.bodyLarge?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
          bodyMedium: base.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.5,
          ),
          bodySmall: base.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            height: 1.4,
          ),
          labelLarge: base.labelLarge?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
          labelMedium: base.labelMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          labelSmall: base.labelSmall?.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.2,
          ),
        )
        .apply(
          bodyColor: baseColor,
          displayColor: baseColor,
        );
  }

  /// Wordmark style — the "Uniflex" text logo. Tight tracking, heavy
  /// weight, brand emerald. Used until a real logo asset exists.
  static TextStyle wordmark({double fontSize = 28}) {
    return GoogleFonts.inter(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      color: AppColors.emerald,
    );
  }
}
