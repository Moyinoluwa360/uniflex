import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// The two [ThemeData] instances the whole app runs on (UI Polish 1).
///
/// Built ENTIRELY from the [AppColors] tokens: there is exactly one place
/// that decides what light and dark look like. Student, Rider and Admin all
/// use these — no role has its own theme, and feature files must not branch
/// on brightness (use `context.colors`).
abstract final class AppTheme {
  static ThemeData get light => _build(AppColors.light, Brightness.light);
  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final textTheme = AppTypography.textTheme(c);
    final isDark = brightness == Brightness.dark;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: c.brand,
      onPrimary: c.onBrand,
      primaryContainer: c.surfaceRaised,
      onPrimaryContainer: c.brandText,
      secondary: c.brand,
      onSecondary: c.onBrand,
      secondaryContainer: c.surfaceRaised,
      onSecondaryContainer: c.brandText,
      tertiary: c.statusAmber,
      onTertiary: c.onBrand,
      error: c.dangerText,
      onError: c.onDangerSolid,
      errorContainer: c.surfaceRaised,
      onErrorContainer: c.dangerText,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.borderStrong,
      outlineVariant: c.border,
      shadow: const Color(0xFF000000),
      scrim: const Color(0xFF000000),
      surfaceTint: Colors.transparent,
      inverseSurface: c.textPrimary,
      onInverseSurface: c.background,
      inversePrimary: c.brandText,
    );

    RoundedRectangleBorder shape(double r, {BorderSide side = BorderSide.none}) =>
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(r),
          side: side,
        );

    final buttonShape = shape(AppRadius.button);
    const buttonSize = Size(0, AppSpacing.controlHeight);
    const buttonPad = EdgeInsets.symmetric(horizontal: AppSpacing.lg);

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.input),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: <ThemeExtension<dynamic>>[c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      cardColor: c.surface,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: AppTypography.fontFamily,
      dividerColor: c.border,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.title(c),
        iconTheme: IconThemeData(color: c.textSecondary, size: 22),
        actionsIconTheme: IconThemeData(color: c.textSecondary, size: 22),
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: shape(AppRadius.card, side: BorderSide(color: c.border)),
      ),
      // Buttons: brand fill / onBrand label. No shadow, no gradient. (Orange
      // is for ads and the cart button only — it is not a button default.)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          disabledBackgroundColor: c.surfaceRaised,
          disabledForegroundColor: c.textTertiary,
          textStyle: AppTypography.button(c.onBrand),
          minimumSize: buttonSize,
          padding: buttonPad,
          shape: buttonShape,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.brand,
          foregroundColor: c.onBrand,
          disabledBackgroundColor: c.surfaceRaised,
          disabledForegroundColor: c.textTertiary,
          textStyle: AppTypography.button(c.onBrand),
          minimumSize: buttonSize,
          padding: buttonPad,
          shape: buttonShape,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          disabledForegroundColor: c.textTertiary,
          side: BorderSide(color: c.borderStrong),
          textStyle: AppTypography.button(c.textPrimary),
          minimumSize: buttonSize,
          padding: buttonPad,
          shape: buttonShape,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.brandText,
          disabledForegroundColor: c.textTertiary,
          textStyle: AppTypography.buttonSmall(c.brandText),
          shape: shape(AppRadius.buttonSmall),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: c.textSecondary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        constraints: const BoxConstraints(minHeight: AppSpacing.controlHeight),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 14,
        ),
        hintStyle: AppTypography.body(c).copyWith(color: c.textTertiary),
        labelStyle: AppTypography.meta(c),
        floatingLabelStyle: AppTypography.meta(c).copyWith(color: c.brandText),
        helperStyle: AppTypography.caption(c),
        errorStyle: AppTypography.caption(c).copyWith(color: c.dangerText),
        prefixIconColor: c.textSecondary,
        suffixIconColor: c.textSecondary,
        border: inputBorder(c.border),
        enabledBorder: inputBorder(c.border),
        disabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(c.brand, 1.5),
        errorBorder: inputBorder(c.dangerText),
        focusedErrorBorder: inputBorder(c.dangerText, 1.5),
      ),
      // Cursor + selection: green, never the platform blue.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.brand,
        selectionColor: c.brand.withValues(alpha: 0.30),
        selectionHandleColor: c.brand,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape(AppRadius.cardLarge, side: BorderSide(color: c.border)),
        titleTextStyle: AppTypography.title(c),
        contentTextStyle: AppTypography.meta(c),
        barrierColor: AppColors.barrier,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: AppColors.barrier,
        dragHandleColor: c.borderStrong,
        dragHandleSize: const Size(36, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceRaised,
        contentTextStyle: AppTypography.body(c).copyWith(fontSize: 14),
        actionTextColor: c.brandText,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: shape(AppRadius.control, side: BorderSide(color: c.borderStrong)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.textPrimary,
        unselectedLabelColor: c.textSecondary,
        labelStyle: AppTypography.buttonSmall(c.textPrimary),
        unselectedLabelStyle: AppTypography.buttonSmall(c.textSecondary),
        indicatorColor: c.brand,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: c.border,
        overlayColor: WidgetStatePropertyAll(c.brand.withValues(alpha: 0.08)),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        textColor: c.textPrimary,
        titleTextStyle: AppTypography.body(c),
        subtitleTextStyle: AppTypography.caption(c),
        minVerticalPadding: 8,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.brand,
        disabledColor: c.surfaceRaised,
        side: BorderSide(color: c.borderStrong),
        shape: const StadiumBorder(),
        labelStyle: AppTypography.buttonSmall(c.textPrimary),
        secondaryLabelStyle: AppTypography.buttonSmall(c.onBrand),
        checkmarkColor: c.onBrand,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        pressElevation: 0,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Color(0xFFFFFFFF)),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : Colors.transparent,
        ),
        checkColor: WidgetStatePropertyAll(c.onBrand),
        side: BorderSide(color: c.borderStrong, width: 1.5),
        shape: shape(5),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.brand : c.borderStrong,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brand,
        linearTrackColor: c.surfaceRaised,
        circularTrackColor: Colors.transparent,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: shape(AppRadius.control, side: BorderSide(color: c.borderStrong)),
        textStyle: AppTypography.body(c),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: c.promoOrangeBadge,
        textColor: c.onDangerSolid,
      ),
      // Kept until the floating glass bar replaces it (UI Polish 2).
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: c.background,
        selectedItemColor: c.brandText,
        unselectedItemColor: c.textSecondary,
        selectedLabelStyle: AppTypography.navLabel(c.brandText),
        unselectedLabelStyle: AppTypography.navLabel(c.textSecondary),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Native, platform-correct transitions — Cupertino swipe-back on
          // iOS, predictive back on Android.
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        },
      ),
    );
  }
}
