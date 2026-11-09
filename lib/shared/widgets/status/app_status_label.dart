import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// How a status should look. Status is a dot + words, **never a coloured
/// pill**.
enum StatusTone {
  /// Waiting on someone (placed, in the rider pool, awaiting payment).
  waiting,

  /// Happening now (rider accepted, preparing, out for delivery).
  live,

  /// Finished fine.
  done,

  /// Cancelled.
  cancelled,
}

/// An 8px dot, an 8px gap, then the text (13/600 textSecondary). The `live`
/// dot gets a soft 3px ring.
class AppStatusLabel extends StatelessWidget {
  const AppStatusLabel({super.key, required this.tone, required this.text});

  final StatusTone tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final dot = switch (tone) {
      StatusTone.waiting => c.statusAmber,
      StatusTone.live => c.brand,
      StatusTone.done => c.textTertiary,
      StatusTone.cancelled => c.dangerText,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          key: const ValueKey('status-dot'),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: dot,
            shape: BoxShape.circle,
            boxShadow: tone == StatusTone.live
                ? [
                    BoxShadow(
                      color: dot.withValues(alpha: 0.22),
                      spreadRadius: 3,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.sectionLabel(c).copyWith(letterSpacing: 0),
          ),
        ),
      ],
    );
  }
}
