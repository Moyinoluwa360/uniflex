/// Spacing and radius constants — matches the visual design handoff's
/// Geometry panel exactly. Keeps card/button/screen rhythm consistent so
/// the app doesn't accumulate one-off paddings per screen.
abstract final class AppSpacing {
  /// Base unit every other spacing value is a multiple of.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Screen edge padding, per the design's Geometry panel — deliberately
  /// not the same as [lg]; use this specifically for the left/right
  /// padding a screen's root content sits in.
  static const double screenGutter = 20;

  /// Gap between cards in a list/grid.
  static const double cardGap = 12;

  /// Height of a standard control (button, input) per the design.
  static const double controlHeight = 56;

  /// Minimum hit target for any tappable element (accessibility floor).
  static const double minTapTarget = 44;
}

abstract final class AppRadius {
  /// Small controls: chips, inputs, small buttons.
  static const double control = 14;

  /// Cards.
  static const double card = 22;

  /// Prominent surfaces: bottom sheets, hero cards.
  static const double sheet = 32;

  /// Pill radius for buttons.
  static const double pill = 100;
}
