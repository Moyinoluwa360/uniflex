import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The Uniflex colour tokens (UI Polish 1).
///
/// Read them as `context.colors.surface`, `context.colors.brandText`, ... —
/// never write a hex value or `Colors.x` outside `lib/shared/theme/`.
/// Every token has a light AND a dark value, so a screen can never look right
/// in one theme and broken in the other.
///
/// Colour rules (enforced by `test/ui_guard_test.dart`):
///  * Cards are plain `surface` + `border`. No tinted fills, no glow.
///  * Green (`brand`) = the main action, positive money, "live" status.
///  * Orange (`promoOrange*`) = ads/promos and the cart button ONLY.
///  * Red = warnings (`dangerText`). `dangerSolid` only on the final confirm
///    inside a dialog. Purple and blue are retired.
///  * Status is a dot + words (`AppStatusLabel`), never a coloured pill.
///
/// The old static palette (`emerald`, `orange`, `info`, ...) was deleted in
/// UI Polish 2; `test/ui_polish/ui_guard_test.dart` fails if a raw or legacy
/// colour appears outside `lib/shared/theme/`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.segmentOn,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.onBrand,
    required this.brandText,
    required this.dangerText,
    required this.dangerSolid,
    required this.onDangerSolid,
    required this.statusAmber,
    required this.promoOrangeStart,
    required this.promoOrangeEnd,
    required this.promoOrangeButton,
    required this.promoOrangeBadge,
    required this.glassFill,
    required this.glassBorder,
    required this.glassHighlight,
    required this.navCapsule,
    required this.onNavCapsule,
    required this.navShadow,
    required this.cardShadow,
    required this.headerBorder,
    required this.headerText,
    required this.headerTextSecondary,
    required this.headerPanelFill,
    required this.headerPanelBorder,
    required this.topUpFill,
    required this.topUpLabel,
    required this.searchFill,
    required this.walletBorder,
    required this.walletLabel,
    required this.adNeutral,
    required this.adCircle,
  });

  /// True for the dark token set. Feature code must NOT branch on this; it
  /// exists for the theme and for tokens that are structurally different
  /// (gradients).
  final bool isDark;

  // ── Surfaces ────────────────────────────────────────────────────────
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color segmentOn;
  final Color border;
  final Color borderStrong;

  // ── Text ────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // ── Brand / semantic ────────────────────────────────────────────────
  final Color brand;
  final Color onBrand;

  /// Green used AS TEXT (links, money in).
  final Color brandText;
  final Color dangerText;

  /// Red fill — dialogs only (see `AppButtonVariant.danger`).
  final Color dangerSolid;
  final Color onDangerSolid;
  final Color statusAmber;

  // ── Promo orange (ads + cart button only) ───────────────────────────
  final Color promoOrangeStart;
  final Color promoOrangeEnd;
  final Color promoOrangeButton;
  final Color promoOrangeBadge;

  LinearGradient get promoOrangeGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [promoOrangeStart, promoOrangeEnd],
      );

  // ── Glass + floating nav ────────────────────────────────────────────
  final Color glassFill;
  final Color glassBorder;
  final Color glassHighlight;
  final Color navCapsule;
  final Color onNavCapsule;
  final List<BoxShadow> navShadow;

  /// Soft white-to-clear sheen drawn across the top of the glass bar.
  Gradient get glassSheen => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x29FFFFFF), Color(0x00FFFFFF)],
      );

  /// Card shadow: none in dark, a hairline in light.
  final List<BoxShadow> cardShadow;

  // ── Home header (kept from the original design) ─────────────────────
  final Color headerBorder;
  final Color headerText;
  final Color headerTextSecondary;
  final Color headerPanelFill;
  final Color headerPanelBorder;
  final Color topUpFill;
  final Color topUpLabel;
  final Color searchFill;

  // ── Chart palette (admin money cards / analytics) ──────────────────
  /// Fees series. Same hue as the brand so it reads as "money in".
  Color get chartFees => brand;

  /// Food-payments series. Amber, never the promo orange.
  Color get chartFood => statusAmber;

  /// Ordered series colours for charts: fees, food, then neutrals.
  List<Color> get chartPalette =>
      [chartFees, chartFood, textSecondary, textTertiary];

  LinearGradient get homeHeaderGradient => isDark
      ? _css(
          165,
          const [Color(0xFF0E4A37), Color(0xFF0A2B21), Color(0xFF0A1410)],
          const [0, 0.58, 1])
      : _css(165, const [Color(0xFF08855F), Color(0xFF05694B)], const [0, 1]);

  // ── Wallet card (always dark green, white text) ─────────────────────
  final Color walletBorder;
  final Color walletLabel;

  LinearGradient get walletCardGradient => isDark
      ? _css(160, const [Color(0xFF10241D), Color(0xFF0A1410)], const [0, 1])
      : _css(160, const [Color(0xFF0B3D2E), Color(0xFF082A20)], const [0, 1]);

  /// Radial glow painted OVER [walletCardGradient] (top-right corner).
  RadialGradient get walletCardGlow => RadialGradient(
        center: Alignment.topRight,
        radius: 1.2,
        colors: [
          isDark ? const Color(0x3D10B981) : const Color(0x5734D399),
          const Color(0x0010B981),
        ],
        stops: const [0, 0.6],
      );

  // ── Neutral ad card ─────────────────────────────────────────────────
  final Color adNeutral;
  final Color adCircle;

  // ── Helpers ─────────────────────────────────────────────────────────

  /// CSS-style `linear-gradient(<deg>deg, ...)`: 0° = up, 90° = right,
  /// 180° = down.
  static LinearGradient _css(
      double deg, List<Color> colors, List<double> stops) {
    final a = deg * math.pi / 180;
    final dx = math.sin(a);
    final dy = -math.cos(a);
    return LinearGradient(
      begin: Alignment(-dx, -dy),
      end: Alignment(dx, dy),
      colors: colors,
      stops: stops,
    );
  }

  /// Same helper, public, for the tier headers.
  static LinearGradient cssLinear(
          double deg, List<Color> colors, List<double> stops) =>
      _css(deg, colors, stops);

  /// Black 50% — dialog and sheet backdrop (same in both themes).
  static const Color barrier = Color(0x80000000);

  // ── Fixed tokens (identical in light and dark) ──────────────────────
  /// The one orange allowed outside promos and the cart: the Home bell's
  /// unread dot.
  static const Color notifyDot = Color(0xFFF97316);

  /// Splash screen (brand moment, same in both themes).
  static const List<Color> splashGradient = [
    Color(0xFF12C48C),
    Color(0xFF10B981),
    Color(0xFF0E9E74),
    Color(0xFFF97316),
  ];
  static const Color splashHighlightStart = Color.fromRGBO(255, 255, 255, 0.34);
  static const Color splashHighlightEnd = Color.fromRGBO(255, 255, 255, 0.0);
  static const Color splashShadow = Color.fromRGBO(6, 46, 35, 0.18);

  /// WhatsApp brand green (the "Message on WhatsApp" affordance; third-party
  /// brand colour, same in both themes).
  static const Color whatsapp = Color(0xFF25D366);

  /// Ink that always sits ON an image/ad/dark surface (white).
  static const Color onMedia = Color(0xFFFFFFFF);

  /// Near-black used for the dark ad card and for scrims over photos.
  static const Color adDark = Color(0xFF101312);

  /// Dark glass chip over a photo: rgba(10,12,11,.45).
  static const Color glassChipFill = Color(0x730A0C0B);

  /// Wallet card text/ink (always on dark green).
  static const Color onWallet = Color(0xFFFFFFFF);

  /// Home header base colour (dot borders sit on it).
  Color get headerSolid =>
      isDark ? const Color(0xFF0E4A37) : const Color(0xFF08855F);

  /// Icon/placeholder colour inside the Home search field.
  Color get headerSearchInk => isDark ? headerTextSecondary : textTertiary;

  // ── Token sets ──────────────────────────────────────────────────────

  static const AppColors dark = AppColors(
    isDark: true,
    background: Color(0xFF0A0C0B),
    surface: Color(0xFF121614),
    surfaceRaised: Color(0xFF1A201D),
    segmentOn: Color(0xFF2A322E),
    border: Color(0x14FFFFFF), // white 8%
    borderStrong: Color(0x2EFFFFFF), // white 18%
    textPrimary: Color(0xFFF3F6F4),
    textSecondary: Color(0xFFA5AFA9),
    textTertiary: Color(0xFF7E8984),
    brand: Color(0xFF10B981),
    onBrand: Color(0xFF04140E),
    brandText: Color(0xFF34D399),
    dangerText: Color(0xFFF87171),
    dangerSolid: Color(0xFFDC2626),
    onDangerSolid: Color(0xFFFFFFFF),
    statusAmber: Color(0xFFF5B445),
    promoOrangeStart: Color(0xFFF26A1B),
    promoOrangeEnd: Color(0xFFD9480F),
    promoOrangeButton: Color(0xFFF26A1B),
    promoOrangeBadge: Color(0xFFC2410C),
    glassFill: Color(0x8528302C), // rgba(40,48,44,.52)
    glassBorder: Color(0x24FFFFFF), // white 14%
    glassHighlight: Color(0x3DFFFFFF), // white 24%
    navCapsule: Color(0x29FFFFFF), // white 16%
    onNavCapsule: Color(0xFFFFFFFF),
    navShadow: [
      BoxShadow(
        color: Color(0x80000000),
        offset: Offset(0, 14),
        blurRadius: 34,
      ),
    ],
    cardShadow: [],
    headerBorder: Color(0x3810B981), // rgba(16,185,129,.22)
    headerText: Color(0xFFF3F6F4),
    headerTextSecondary: Color(0xC7F3F6F4), // 78%
    headerPanelFill: Color(0x12FFFFFF), // white 7%
    headerPanelBorder: Color(0x24FFFFFF), // white 14%
    topUpFill: Color(0xFF10B981),
    topUpLabel: Color(0xFF04140E),
    searchFill: Color(0x40000000), // black 25%
    walletBorder: Color(0x14FFFFFF), // white 8%
    walletLabel: Color(0xC7FFFFFF), // white 78%
    adNeutral: Color(0xFF1C211F),
    adCircle: Color(0x0FFFFFFF), // white 6%
  );

  static const AppColors light = AppColors(
    isDark: false,
    background: Color(0xFFF5F6F5),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEDF0EE),
    segmentOn: Color(0xFFFFFFFF),
    border: Color(0x140E1210), // #0E1210 8%
    borderStrong: Color(0x2E0E1210), // #0E1210 18%
    textPrimary: Color(0xFF0E1210),
    textSecondary: Color(0xFF4C5752),
    textTertiary: Color(0xFF66726C),
    brand: Color(0xFF10B981),
    onBrand: Color(0xFF04140E),
    brandText: Color(0xFF047857),
    dangerText: Color(0xFFC62828),
    dangerSolid: Color(0xFFDC2626),
    onDangerSolid: Color(0xFFFFFFFF),
    statusAmber: Color(0xFFD98A0B),
    promoOrangeStart: Color(0xFFF26A1B),
    promoOrangeEnd: Color(0xFFD9480F),
    promoOrangeButton: Color(0xFFF26A1B),
    promoOrangeBadge: Color(0xFFC2410C),
    glassFill: Color(0x94FFFFFF), // rgba(255,255,255,.58)
    glassBorder: Color(0xD9FFFFFF), // white 85%
    glassHighlight: Color(0xFFFFFFFF),
    navCapsule: Color(0xFF0E1210),
    onNavCapsule: Color(0xFFFFFFFF),
    navShadow: [
      BoxShadow(
        color: Color(0x290E1210), // rgba(14,18,16,.16)
        offset: Offset(0, 14),
        blurRadius: 34,
      ),
    ],
    cardShadow: [
      BoxShadow(
        color: Color(0x0A0E1210), // rgba(14,18,16,.04)
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
    headerBorder: Color(0x00000000),
    headerText: Color(0xFFFFFFFF),
    headerTextSecondary: Color(0xE0FFFFFF), // 88%
    headerPanelFill: Color(0x24FFFFFF), // white 14%
    headerPanelBorder: Color(0x57FFFFFF), // white 34%
    topUpFill: Color(0xFFFFFFFF),
    topUpLabel: Color(0xFF0E1210),
    searchFill: Color(0xFFFFFFFF),
    walletBorder: Color(0x14FFFFFF), // white 8% (card is dark in both themes)
    walletLabel: Color(0xC7FFFFFF),
    adNeutral: Color(0xFFE4E9E6),
    adCircle: Color(0x0D0E1210), // #0E1210 5%
  );

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? textPrimary,
    Color? brand,
  }) {
    return AppColors(
      isDark: isDark,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      segmentOn: segmentOn,
      border: border ?? this.border,
      borderStrong: borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary,
      textTertiary: textTertiary,
      brand: brand ?? this.brand,
      onBrand: onBrand,
      brandText: brandText,
      dangerText: dangerText,
      dangerSolid: dangerSolid,
      onDangerSolid: onDangerSolid,
      statusAmber: statusAmber,
      promoOrangeStart: promoOrangeStart,
      promoOrangeEnd: promoOrangeEnd,
      promoOrangeButton: promoOrangeButton,
      promoOrangeBadge: promoOrangeBadge,
      glassFill: glassFill,
      glassBorder: glassBorder,
      glassHighlight: glassHighlight,
      navCapsule: navCapsule,
      onNavCapsule: onNavCapsule,
      navShadow: navShadow,
      cardShadow: cardShadow,
      headerBorder: headerBorder,
      headerText: headerText,
      headerTextSecondary: headerTextSecondary,
      headerPanelFill: headerPanelFill,
      headerPanelBorder: headerPanelBorder,
      topUpFill: topUpFill,
      topUpLabel: topUpLabel,
      searchFill: searchFill,
      walletBorder: walletBorder,
      walletLabel: walletLabel,
      adNeutral: adNeutral,
      adCircle: adCircle,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    // Gradients and shadows are chosen by the nearer theme; colours blend.
    final near = t < 0.5 ? this : other;
    return AppColors(
      isDark: near.isDark,
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      segmentOn: l(segmentOn, other.segmentOn),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      brandText: l(brandText, other.brandText),
      dangerText: l(dangerText, other.dangerText),
      dangerSolid: l(dangerSolid, other.dangerSolid),
      onDangerSolid: l(onDangerSolid, other.onDangerSolid),
      statusAmber: l(statusAmber, other.statusAmber),
      promoOrangeStart: l(promoOrangeStart, other.promoOrangeStart),
      promoOrangeEnd: l(promoOrangeEnd, other.promoOrangeEnd),
      promoOrangeButton: l(promoOrangeButton, other.promoOrangeButton),
      promoOrangeBadge: l(promoOrangeBadge, other.promoOrangeBadge),
      glassFill: l(glassFill, other.glassFill),
      glassBorder: l(glassBorder, other.glassBorder),
      glassHighlight: l(glassHighlight, other.glassHighlight),
      navCapsule: l(navCapsule, other.navCapsule),
      onNavCapsule: l(onNavCapsule, other.onNavCapsule),
      navShadow: near.navShadow,
      cardShadow: near.cardShadow,
      headerBorder: l(headerBorder, other.headerBorder),
      headerText: l(headerText, other.headerText),
      headerTextSecondary: l(headerTextSecondary, other.headerTextSecondary),
      headerPanelFill: l(headerPanelFill, other.headerPanelFill),
      headerPanelBorder: l(headerPanelBorder, other.headerPanelBorder),
      topUpFill: l(topUpFill, other.topUpFill),
      topUpLabel: l(topUpLabel, other.topUpLabel),
      searchFill: l(searchFill, other.searchFill),
      walletBorder: l(walletBorder, other.walletBorder),
      walletLabel: l(walletLabel, other.walletLabel),
      adNeutral: l(adNeutral, other.adNeutral),
      adCircle: l(adCircle, other.adCircle),
    );
  }
}

/// `context.colors` — the active token set. Falls back to the set matching
/// the ambient brightness when a test (or an overlay) has no [AppTheme]
/// above it, so the shared widgets never crash.
extension AppColorsContext on BuildContext {
  AppColors get colors {
    final theme = Theme.of(this);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark
            ? AppColors.dark
            : AppColors.light);
  }
}
