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
  static const double navBarBottomGap = 22;
  static const double navBarSideGap = 16;

  /// Bar height + the gap under it: the part of the bottom clearance that is
  /// the same on every phone. Add the device's bottom safe area for the full
  /// figure — use [navClearanceOf].
  static const double navClearance = navBarHeight + navBarBottomGap;

  /// Bottom padding a scrollable needs so its last item is never hidden
  /// under the floating bar: bar height + 22 + the safe-area bottom.
  static double navClearanceOf(BuildContext context) =>
      navClearance + MediaQuery.paddingOf(context).bottom;
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
