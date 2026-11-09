import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// Section label: 13/600 textSecondary, +0.01 em tracking.
class AppSectionLabel extends StatelessWidget {
  const AppSectionLabel(this.text, {super.key, this.padding});

  final String text;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: AppTypography.sectionLabel(context.colors));
    return padding == null ? label : Padding(padding: padding!, child: label);
  }
}
