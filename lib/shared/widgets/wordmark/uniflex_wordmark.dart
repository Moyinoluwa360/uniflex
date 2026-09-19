import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// The "Uniflex" text wordmark, per the design handoff ("wordmark only,
/// never the mark") — the app icon (assets/icon/app_icon.png) is the only
/// place the U-shaped logo mark itself appears. Every place that would
/// show branding in-app should use this widget rather than hardcoding
/// the brand text.
class UniflexWordmark extends StatelessWidget {
  const UniflexWordmark({super.key, this.fontSize = 28, this.color});

  final double fontSize;

  /// Overrides the default brand-emerald colour — used on the splash
  /// screen's gradient background, where the wordmark is white.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      'Uniflex',
      style: AppTypography.wordmark(fontSize: fontSize, color: color),
    );
  }
}
