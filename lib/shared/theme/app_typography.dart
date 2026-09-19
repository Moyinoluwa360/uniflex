import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Typography scale — **Clash Display** (Semibold) for the wordmark and all
/// display/headline slots (anything that acts as a screen title or section
/// header), **Switzer** for body text, buttons, labels, and all other UI
/// text. Both are bundled as local assets (see `assets/fonts/` and the
/// `fonts:` section of pubspec.yaml) — this is the real brand type from the
/// design handoff, not a Google Fonts approximation.
///
/// Clash Display ships here as a single Semibold (600) weight, which is the
/// only weight the design uses for display/titles, so every display slot is
/// set at w600. Switzer ships in Regular (400), Medium (500), and Semibold
/// (600).
///
/// Built on Material's type scale so it plugs directly into
/// [ThemeData.textTheme] and every built-in widget picks it up
/// automatically. Only the four sizes the design specifies (H1, H2,
/// Body, Meta) map to a named design token; the remaining Material slots
/// are filled in at sensible sizes so nothing is left unstyled.
abstract final class AppTypography {
  /// Family names as declared in pubspec.yaml's `fonts:` section.
  static const String displayFamily = 'ClashDisplay';
  static const String bodyFamily = 'Switzer';

  static TextTheme textTheme(Color baseColor) {
    return TextTheme(
      // ---- Display / Headlines — Clash Display 600 ----
      displayLarge: _display(40, FontWeight.w600, baseColor),
      displayMedium: _display(34, FontWeight.w600, baseColor),
      headlineLarge: _display(32, FontWeight.w600, baseColor),
      // H1 — Clash Display 600/28. Screen titles ("Good morning").
      headlineMedium: _display(28, FontWeight.w600, baseColor),
      headlineSmall: _display(24, FontWeight.w600, baseColor),
      titleLarge: _display(22, FontWeight.w600, baseColor),
      // H2 — Clash Display 600/20. Section headers ("Vendors near you").
      titleMedium: _display(20, FontWeight.w600, baseColor),
      titleSmall: _display(17, FontWeight.w600, baseColor),
      // ---- Body / Labels — Switzer ----
      bodyLarge: _body(17, FontWeight.w400, baseColor, height: 1.5),
      // Body — Switzer 400/15.
      bodyMedium: _body(15, FontWeight.w400, baseColor, height: 1.5),
      bodySmall: _body(14, FontWeight.w400, baseColor, height: 1.4),
      labelLarge: _body(15, FontWeight.w600, baseColor),
      labelMedium: _body(14, FontWeight.w500, baseColor),
      // Meta — Switzer 500/13. Fine print ("15-20 min · ₦300 delivery").
      labelSmall: _body(13, FontWeight.w500, baseColor),
    );
  }

  static TextStyle _display(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
  }) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
      // Clash Display reads tight — a small negative tracking on the larger
      // display sizes keeps titles crisp, matching the handoff.
      letterSpacing: size * -0.02,
    );
  }

  static TextStyle _body(
    double size,
    FontWeight weight,
    Color color, {
    double? height,
  }) {
    return TextStyle(
      fontFamily: bodyFamily,
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: height,
    );
  }

  /// Wordmark style — the "Uniflex" text logo. Clash Display 600,
  /// −3.5% tracking, brand emerald. Used by [UniflexWordmark].
  static TextStyle wordmark({double fontSize = 40, Color? color}) {
    return TextStyle(
      fontFamily: displayFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      letterSpacing: fontSize * -0.035,
      color: color ?? AppColors.emerald,
    );
  }
}
