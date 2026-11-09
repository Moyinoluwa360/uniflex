import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// A delivery PIN drawn as one neutral box per digit (surface raised, strong
/// hairline, tabular digits). Tapping copies the PIN — the same clipboard call
/// and "PIN copied" snackbar the screens had before.
class PinDigitBoxes extends StatelessWidget {
  const PinDigitBoxes({
    super.key,
    required this.pin,
    this.copiedMessage = 'PIN copied',
  });

  final String pin;

  /// Snackbar text after a tap (screens keep their own wording).
  final String copiedMessage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: pin));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(copiedMessage),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final digit in pin.split(''))
            Container(
              width: 44,
              height: 52,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: c.borderStrong),
              ),
              alignment: Alignment.center,
              child: Text(
                digit,
                style: AppTypography.tabular(
                  Theme.of(context)
                      .textTheme
                      .headlineMedium!
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.sm),
          Icon(AppIcons.copy, size: 16, color: c.textSecondary),
        ],
      ),
    );
  }
}
