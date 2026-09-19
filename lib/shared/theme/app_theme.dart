import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The two [ThemeData] instances the whole app runs on. Student, Rider,
/// and Admin shells all consume these directly — no role has its own
/// theme. Only [AppColors]/[AppTypography]/[AppSpacing] should be edited
/// to change the app's look; avoid inlining styling in screens.
///
/// Dark mode is a deliberately separate system from light mode, not a
/// filter over it — see the design handoff's "How dark mode is built"
/// panel, summarised in the [dark] getter below.
abstract final class AppTheme {
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.emerald,
      onPrimary: AppColors.pureWhite,
      primaryContainer: Color(0xFFD1FAE5),
      onPrimaryContainer: AppColors.emerald,
      secondary: AppColors.orange,
      onSecondary: AppColors.pureWhite,
      secondaryContainer: Color(0xFFFFEDD5),
      onSecondaryContainer: AppColors.orange,
      surface: AppColors.pureWhite,
      onSurface: AppColors.matteBlack,
      surfaceContainerHighest: AppColors.softGrey,
      error: AppColors.error,
      onError: AppColors.pureWhite,
      outline: AppColors.borderGrey,
    );

    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.pureWhite,
      cardColor: AppColors.pureWhite,
      dividerColor: AppColors.borderGrey,
      brightness: Brightness.light,
    );
  }

  static ThemeData get dark {
    // Emerald's dark-mode job changes: it drops from a full field to a
    // deep gradient accent, and orange never dims — it stays full-chroma
    // in both themes (see AppColors doc comments).
    const colorScheme = ColorScheme.dark(
      primary: AppColors.emerald,
      onPrimary: AppColors.matteBlack,
      primaryContainer: AppColors.darkEmerald,
      onPrimaryContainer: AppColors.emerald,
      secondary: AppColors.orange,
      onSecondary: AppColors.matteBlack,
      secondaryContainer: AppColors.darkEmerald,
      onSecondaryContainer: AppColors.orange,
      surface: AppColors.darkCard,
      onSurface: AppColors.darkInkPrimary,
      surfaceContainerHighest: AppColors.darkSurface,
      error: AppColors.error,
      onError: AppColors.pureWhite,
      outline: AppColors.darkHairline,
    );

    return _build(
      colorScheme: colorScheme,
      scaffoldBackground: AppColors.darkCanvas,
      cardColor: AppColors.darkCard,
      dividerColor: AppColors.darkHairline,
      brightness: Brightness.dark,
    );
  }

  static ThemeData _build({
    required ColorScheme colorScheme,
    required Color scaffoldBackground,
    required Color cardColor,
    required Color dividerColor,
    required Brightness brightness,
  }) {
    final textTheme = AppTypography.textTheme(colorScheme.onSurface);
    final isDark = brightness == Brightness.dark;
    final secondaryInk = isDark ? AppColors.darkInkSecondary : AppColors.mediumGrey;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBackground,
      textTheme: textTheme,
      fontFamily: textTheme.bodyMedium?.fontFamily,
      dividerColor: dividerColor,
      splashFactory: InkSparkle.splashFactory,

      appBarTheme: AppBarTheme(
        backgroundColor: scaffoldBackground,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: dividerColor),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: AppColors.pureWhite,
          disabledBackgroundColor: colorScheme.outline,
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(color: dividerColor),
          textStyle: textTheme.labelLarge,
          minimumSize: const Size.fromHeight(AppSpacing.controlHeight),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: textTheme.labelLarge,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : AppColors.softGrey,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: secondaryInk),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.emerald, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: const BorderSide(color: AppColors.error, width: 1.5),
        ),
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: scaffoldBackground,
        selectedItemColor: AppColors.emerald,
        unselectedItemColor: secondaryInk,
        selectedLabelStyle: textTheme.labelSmall,
        unselectedLabelStyle: textTheme.labelSmall,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.onSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: colorScheme.surface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
      ),

      dividerTheme: DividerThemeData(color: dividerColor, thickness: 1),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Native, platform-correct transitions rather than a generic
          // cross-platform slide — Cupertino swipe-back on iOS, predictive
          // back gesture on Android (matches Android 13+ system behaviour).
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
