import 'package:flutter/widgets.dart';

/// Spacing and radius constants (UI Polish 1). Keeps card/button/screen
/// rhythm consistent so the app doesn't accumulate one-off paddings.
abstract final class AppSpacing {
  /// Base unit every other spacing value is a multiple of.
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Left/right padding a screen's root content sits in.
  static const double screenGutter = 20;

  /// Card inner padding.
  static const double cardPadding = 16;

  /// Gap between cards in a list/grid.
  static const double cardGap = 12;

  /// Height of a standard control (medium button, input).
  static const double controlHeight = 52;

  /// Height of a small button.
  static const double controlHeightSmall = 40;

  /// Minimum height of a list row.
  static const double listRowMin = 56;

  /// Minimum hit target for any tappable element (accessibility floor).
  static const double minTapTarget = 44;

  // ── Floating glass nav bar ──────────────────────────────────────────
  static const double navBarHeight = 68;
  static const double navBarSideGap = 16;

  /// NAV_BOTTOM_GAP_PT — points from the PHYSICAL bottom edge of the screen
  /// to the bottom edge of the bar, on phones with a home indicator. The
  /// safe-area inset is NOT added on top. The owner may tune this one
  /// number after comparing with the WhatsApp tab bar on their iPhone.
  static const double navBottomGap = 20;

  /// Same gap on phones without a home indicator (bottom inset 0).
  static const double navBottomGapNoIndicator = 12;

  /// Space kept between the bar's top edge and the last scrolled item.
  static const double navBreathing = 12;

  /// The gap for this device: [navBottomGap] with a home indicator,
  /// [navBottomGapNoIndicator] without one.
  static double navBottomGapOf(BuildContext context) =>
      MediaQuery.paddingOf(context).bottom > 0
          ? navBottomGap
          : navBottomGapNoIndicator;

  /// Bar height + gap + breathing room on a phone with a home indicator
  /// (68 + 20 + 12 = 100). Use [navClearanceOf] in widgets.
  static const double navClearance = navBarHeight + navBottomGap + navBreathing;

  /// Bottom padding a scrollable needs so its last item is never hidden
  /// under the floating bar: bar height + this device's gap + 12. Measured
  /// from the physical bottom of the screen (the glass shell's body extends
  /// to it).
  static double navClearanceOf(BuildContext context) =>
      navBarHeight + navBottomGapOf(context) + navBreathing;
}

abstract final class AppRadius {
  /// Inputs, small controls.
  static const double control = 14;

  /// Standard button.
  static const double button = 14;
  static const double buttonSmall = 12;
  static const double input = 14;

  /// Cards.
  static const double card = 20;

  /// Large cards (wallet card, tier header, dialogs).
  static const double cardLarge = 24;

  /// Bottom sheets (top corners).
  static const double sheet = 28;

  /// Bottom corners of the green Home header.
  static const double header = 36;

  static const double segmentedTrack = 14;
  static const double segment = 11;
  static const double iconButton = 12;
  static const double nav = 34;
  static const double thumb = 14;

  /// Chips and pills.
  static const double pill = 100;
}
