import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../buttons/tap_guard.dart';

/// Title row of a group of inputs: 13/600 `textSecondary` (+0.01 em), 2 px in
/// from the left, 8 px above the first input, with an optional right-aligned
/// note (12.5/500 `textTertiary`, e.g. "Optional") — only where the form
/// already says so. No card, tint or divider: whitespace does the grouping.
class AppFormSection extends StatelessWidget {
  const AppFormSection({super.key, required this.title, this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: AppTypography.sectionLabel(c)),
            ),
          ),
          if (note != null)
            Text(
              note!,
              style: AppTypography.caption(c).copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

/// An outlined option for few, mutually exclusive choices: height 44, radius
/// 12, 1 px `borderStrong`, label 14/600. Selected: 1.5 px `brand` border,
/// `brandText` label and a 16 px check.
class AppChoiceChip extends StatefulWidget {
  const AppChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<AppChoiceChip> createState() => _AppChoiceChipState();
}

class _AppChoiceChipState extends State<AppChoiceChip> {
  final _guard = TapGuard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sel = widget.selected;
    return Semantics(
      button: true,
      selected: sel,
      inMutuallyExclusiveGroup: true,
      label: widget.label,
      child: ExcludeSemantics(
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.buttonSmall),
            side: BorderSide(
              color: sel ? c.brand : c.borderStrong,
              width: sel ? 1.5 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap:
                widget.onTap == null ? null : () => _guard.run(widget.onTap!),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (sel) ...[
                      Icon(AppIcons.check, size: 16, color: c.brandText),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        style: AppTypography.buttonSmall(
                            sel ? c.brandText : c.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A consent / checkbox row: 22 px box (radius 6, 1.5 px `borderStrong`;
/// checked = `brand` fill with an `onBrand` check), 12 px gap, 14
/// `textSecondary` text. The whole row is one tap target, at least 48 high.
/// Pass [label] for plain text, or [child] (e.g. a `Text.rich` with
/// `brandText` / 600 links) for text that has links.
class AppCheckboxRow extends StatelessWidget {
  const AppCheckboxRow({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.child,
  }) : assert(label != null || child != null);

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      checked: value,
      label: label,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: value ? c.brand : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: value ? c.brand : c.borderStrong,
                    width: 1.5,
                  ),
                ),
                child: value
                    ? Icon(AppIcons.check, size: 16, color: c.onBrand)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DefaultTextStyle(
                  style: AppTypography.meta(c),
                  child: child ?? Text(label!),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two short inputs side by side (equal width, 10 px apart) where a form
/// already pairs them. Each half needs ~160 px to show its text, so when the
/// row is too narrow for the current text size they stack instead (same order,
/// 10 px apart) rather than cutting the text off.
class AppFieldPair extends StatelessWidget {
  const AppFieldPair({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return LayoutBuilder(builder: (context, cons) {
      if (cons.maxWidth / scale < 320) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [left, const SizedBox(height: 10), right],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      );
    });
  }
}
