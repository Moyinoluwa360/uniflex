import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A small dark glass chip that sits on top of a photo (the vendor "Major"
/// tag): padding 5×10, fully round, fill rgba(10,12,11,.45), blur 12, 1px
/// white-20% border, white 12/600 text. Identical in both themes.
class DarkGlassChip extends StatelessWidget {
  const DarkGlassChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.pill);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.glassChipFill,
            borderRadius: radius,
            border: Border.all(
              color: AppColors.onMedia.withValues(alpha: 0.20),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onMedia,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
