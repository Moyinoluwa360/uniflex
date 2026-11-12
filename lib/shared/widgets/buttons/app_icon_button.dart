import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import 'tap_guard.dart';

/// 40×40, radius 12, 1px strong border, 22px icon in textSecondary, with an
/// optional 10px dot badge (colour is passed in so a screen picks it from the
/// tokens). Guarded against double taps like every shared button.
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.badgeColor,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;

  /// Shows a 10px dot in the top-right corner in this colour.
  final Color? badgeColor;
  final String? semanticLabel;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  final TapGuard _guard = TapGuard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppRadius.iconButton);
    final cb = widget.onPressed;
    return Semantics(
      button: true,
      enabled: cb != null,
      label: widget.semanticLabel,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: radius,
                  side: BorderSide(color: c.borderStrong),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  customBorder: RoundedRectangleBorder(borderRadius: radius),
                  onTap: cb == null ? null : () => _guard.run(cb),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: AppIconSize.regular,
                      color: cb == null ? c.textTertiary : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.badgeColor != null)
              Positioned(
                top: -3,
                right: -3,
                child: Container(
                  key: const ValueKey('icon-badge'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: widget.badgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.background, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
