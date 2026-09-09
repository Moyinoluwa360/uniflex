import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// The "Uniflex" text wordmark — stands in for a logo asset until a real
/// one is designed. Every place that would show a logo should use this
/// widget rather than hardcoding the brand text, so a future image asset
/// only needs to be swapped in here.
class UniflexWordmark extends StatelessWidget {
  const UniflexWordmark({super.key, this.fontSize = 28});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text('Uniflex', style: AppTypography.wordmark(fontSize: fontSize));
  }
}
