import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_typography.dart';

enum TrackingStepState {
  /// Finished: filled brand dot with a check.
  done,

  /// Happening now: brand ring with a small filled centre.
  current,

  /// Not reached: a `borderStrong` outline.
  upcoming,
}

/// Vertical order-progress stepper. Presentation only — the screen works out
/// which step is in which [TrackingStepState].
///
/// Connector lines are `brand` between two reached steps and `border`
/// otherwise. State is never colour-only: done has a check, current has a
/// ring + centre, and the label weight follows the state.
class TrackingStepper extends StatelessWidget {
  const TrackingStepper({
    super.key,
    required this.labels,
    required this.states,
  });

  final List<String> labels;
  final List<TrackingStepState> states;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: List.generate(labels.length, (i) {
        final state = states[i];
        final isLast = i == labels.length - 1;
        final reached = state != TrackingStepState.upcoming;
        final nextReached =
            !isLast && states[i + 1] != TrackingStepState.upcoming;

        final Widget dot = switch (state) {
          TrackingStepState.done => Container(
              key: ValueKey('step-done-$i'),
              width: 24,
              height: 24,
              decoration: BoxDecoration(color: c.brand, shape: BoxShape.circle),
              child: Icon(AppIcons.check, size: 15, color: c.onBrand),
            ),
          TrackingStepState.current => Container(
              key: ValueKey('step-current-$i'),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.brand, width: 2),
              ),
              alignment: Alignment.center,
              child: Container(
                width: 10,
                height: 10,
                decoration:
                    BoxDecoration(color: c.brand, shape: BoxShape.circle),
              ),
            ),
          TrackingStepState.upcoming => Container(
              key: ValueKey('step-upcoming-$i'),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.borderStrong, width: 2),
              ),
            ),
        };

        final labelStyle = AppTypography.body(c).copyWith(
          fontWeight: state == TrackingStepState.current
              ? FontWeight.w600
              : FontWeight.w500,
          color: reached ? c.textPrimary : c.textTertiary,
        );

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    dot,
                    if (!isLast)
                      Expanded(
                        child: Container(
                          key: ValueKey('step-line-$i'),
                          width: 2,
                          constraints: const BoxConstraints(minHeight: 20),
                          color: (reached && nextReached) ? c.brand : c.border,
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(top: 1, bottom: isLast ? 0 : 14),
                  child: Text(labels[i], style: labelStyle),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
