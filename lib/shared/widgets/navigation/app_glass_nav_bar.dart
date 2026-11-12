import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_bottom_nav_shell.dart';
import '../buttons/app_tappable.dart';

/// One item of the [AppGlassNavBar].
class AppGlassNavItem {
  const AppGlassNavItem({
    required this.label,
    required this.icon,
    this.badgeCount = 0,
  });

  /// Same icon/label as an existing shell tab (the OUTLINE icon is always
  /// used; the active state is shown by the capsule, not a filled glyph).
  factory AppGlassNavItem.fromTab(AppNavTab tab, {int badgeCount = 0}) =>
      AppGlassNavItem(label: tab.label, icon: tab.icon, badgeCount: badgeCount);

  final String label;
  final IconData icon;
  final int badgeCount;
}

/// The floating glass navigation bar: a rounded capsule whose bottom edge is
/// [AppSpacing.navBottomGap] (20) above the physical bottom of the screen (12
/// on phones without a home indicator), 16px from the sides, 68px tall
/// (radius 34), with a blurred "glass" fill, ONE uniform 1px glass border and
/// a drop shadow painted outside the capsule only. The active item has a filled capsule that SLIDES between
/// tabs (≈280 ms, easeOutCubic; instant when the OS asks for reduced motion).
///
/// It takes the same data the shells already have — a current index and an
/// index callback — and changes no tab/route logic. Wiring it into the shells
/// (with `Scaffold.extendBody: true` and `AppSpacing.navClearanceOf` bottom
/// padding on scrollables) is UI Polish 2.
///
/// Performance: one `BackdropFilter` only, inside a `RepaintBoundary`.
class AppGlassNavBar extends StatelessWidget {
  const AppGlassNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length > 0);

  final List<AppGlassNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  static const double _inset = 6;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final radius = BorderRadius.circular(AppRadius.nav);
    final n = items.length;
    final current = currentIndex.clamp(0, n - 1);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.navBarSideGap,
        0,
        AppSpacing.navBarSideGap,
        // Measured from the physical bottom of the screen; the safe-area
        // inset is deliberately NOT added (Pack 1 / 1.1).
        AppSpacing.navBottomGapOf(context),
      ),
      child: RepaintBoundary(
        child: SizedBox(
          height: AppSpacing.navBarHeight,
          child: CustomPaint(
            // Shadow is painted OUTSIDE the capsule only, so it does not
            // darken the glass from underneath.
            painter: _OuterShadowPainter(AppRadius.nav, c.navShadow),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: DecoratedBox(
                  key: const ValueKey('glass-nav'),
                  // One 1px border, identical on all four sides. No top-only
                  // highlight line or sheen (they made the top edge look
                  // thicker — Pack 1 / 1.2).
                  decoration: BoxDecoration(
                    color: c.glassFill,
                    borderRadius: radius,
                    border: Border.all(color: c.glassBorder),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(_inset),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final itemW = box.maxWidth / n;
                        return Stack(
                          children: [
                            AnimatedPositioned(
                              duration: reduce
                                  ? Duration.zero
                                  : const Duration(milliseconds: 280),
                              curve: Curves.easeOutCubic,
                              left: current * itemW,
                              top: 0,
                              bottom: 0,
                              width: itemW,
                              child: DecoratedBox(
                                key: const ValueKey('nav-capsule'),
                                decoration: BoxDecoration(
                                  color: c.navCapsule,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.nav - _inset,
                                  ),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (var i = 0; i < n; i++)
                                  Expanded(
                                    child: _NavItem(
                                      item: items[i],
                                      active: i == current,
                                      onTap: () {
                                        if (i != current) {
                                          HapticFeedback.selectionClick();
                                        }
                                        onTap(i);
                                      },
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AppGlassNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = active ? c.onNavCapsule : c.textSecondary;
    final icon = Icon(item.icon, size: 22, color: color);
    return Semantics(
      button: true,
      selected: active,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: AppTappable(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.nav - 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            item.badgeCount > 0
                ? Badge(label: Text('${item.badgeCount}'), child: icon)
                : icon,
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.navLabel(color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints [shadows] around an rrect but never inside it.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.radius, this.shadows);

  final double radius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final outside = Path.combine(
      PathOperation.difference,
      Path()
        ..addRect(
            Rect.fromLTWH(-200, -200, size.width + 400, size.height + 400)),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final s in shadows) {
      canvas.drawRRect(rrect.shift(s.offset), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) =>
      old.radius != radius || old.shadows != shadows;
}
