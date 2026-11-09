import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Segmented tabs: a `surfaceRaised` track (radius 14, padding 4) with a
/// highlighted segment (36 high, radius 11) that SLIDES to the chosen tab
/// (200 ms, ease-out).
///
/// Works with both ways tabs are driven today:
///  * pass a [controller] (`TabController` / `DefaultTabController.of`) —
///    the widget follows `controller.index` and calls `animateTo`; or
///  * pass [index] + [onChanged].
///
/// It only draws the control; what each tab SHOWS is untouched.
class AppSegmentedTabs extends StatelessWidget {
  const AppSegmentedTabs({
    super.key,
    required this.labels,
    this.counts,
    this.index = 0,
    this.onChanged,
    this.controller,
  }) : assert(counts == null || counts.length == labels.length);

  final List<String> labels;

  /// Optional count per tab (12.5/600, textTertiary). `null` entries hide it.
  final List<int?>? counts;
  final int index;
  final ValueChanged<int>? onChanged;
  final TabController? controller;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) return _build(context, index);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => _build(context, ctrl.index),
    );
  }

  void _select(int i) {
    final ctrl = controller;
    if (ctrl != null) {
      if (i != ctrl.index) ctrl.animateTo(i);
    }
    onChanged?.call(i);
  }

  Widget _build(BuildContext context, int selected) {
    final c = context.colors;
    final n = labels.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.segmentedTrack),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: LayoutBuilder(
          builder: (context, box) {
            final segW = box.maxWidth / n;
            return SizedBox(
              height: 36,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    left: selected * segW,
                    top: 0,
                    width: segW,
                    height: 36,
                    child: DecoratedBox(
                      key: const ValueKey('segment-highlight'),
                      decoration: BoxDecoration(
                        color: c.segmentOn,
                        borderRadius: BorderRadius.circular(AppRadius.segment),
                        boxShadow: [
                          BoxShadow(
                            color: c.cardShadow.isEmpty
                                ? AppColors.barrier
                                : c.cardShadow.first.color,
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(
                          child: _Segment(
                            label: labels[i],
                            count: counts?[i],
                            selected: i == selected,
                            onTap: () => _select(i),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.segment),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.buttonSmall(
                    selected ? c.textPrimary : c.textSecondary,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: AppTypography.tabular(
                    const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)
                        .copyWith(
                      fontFamily: AppTypography.fontFamily,
                      color: c.textTertiary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
