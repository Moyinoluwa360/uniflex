import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// THE tappable surface (Pack 1 / 1.4). Use it for anything rounded that
/// reacts to a tap instead of a bare `InkWell`.
///
/// Why: an `InkWell` paints its highlight on the nearest `Material`
/// ancestor. When that Material sits OUTSIDE the rounded clip (the Scaffold,
/// for a row inside a rounded card), the highlight comes out as a square
/// behind a rounded component. This wrapper brings its own transparent
/// `Material` with the exact shape, clipped, so the highlight can only ever
/// fill the component's own shape.
///
/// Effect: no ripple wave, just a soft [AppColors.pressOverlay] while pressed.
/// Rows inside a rounded group pass `BorderRadius.zero`; the group's own clip
/// rounds the first/last row's corners.
class AppTappable extends StatelessWidget {
  const AppTappable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = BorderRadius.zero,
    this.shape,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Corner radius of the tappable area. Ignored when [shape] is given.
  final BorderRadius borderRadius;

  /// A non-rectangular shape (e.g. `CircleBorder()`, `StadiumBorder()`).
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = shape ?? RoundedRectangleBorder(borderRadius: borderRadius);
    return Material(
      type: MaterialType.transparency,
      shape: s,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        customBorder: s,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: c.pressOverlay,
        child: child,
      ),
    );
  }
}
