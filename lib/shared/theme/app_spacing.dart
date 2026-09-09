/// Spacing and radius constants. Keeps card/button/screen rhythm consistent
/// so the app doesn't accumulate one-off paddings per screen.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AppRadius {
  /// Standard rounded corner used by cards, sheets, inputs.
  static const double md = 16;

  /// Larger radius for prominent surfaces (bottom sheets, hero cards).
  static const double lg = 24;

  /// Pill radius for buttons and chips.
  static const double pill = 100;
}
