import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../wordmark/uniflex_wordmark.dart';

/// One of the small glass chips on the Login header ("Food", "Deliveries",
/// "Errands"). Static decoration — not tappable.
class AuthHeaderChip {
  const AuthHeaderChip(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// The green header of Login and the sign-up steps (UI Polish 3), built from
/// the Home header tokens (`homeHeaderGradient`, `headerText`, ...). It sits
/// INSIDE the screen's scroll view so the keyboard never squashes it.
///
/// Decoration (clipped, behind the content, never takes a tap): an orange
/// circle top-right (`authAccent`) with two soft halo rings, and a plain white
/// 5% disc bottom-left. **No text is ever drawn on the orange circle**: the
/// title/wordmark are width-limited so they wrap before reaching it.
///
/// * [AppAuthHeader.login] — wordmark, headline, subtitle, three glass chips.
/// * [AppAuthHeader.compact] — glass back button, title, sub-title and an
///   optional [AppStepProgress].
class AppAuthHeader extends StatelessWidget {
  /// Login variant.
  const AppAuthHeader.login({
    super.key,
    required String this.headline,
    required String this.subtitle,
    required List<AuthHeaderChip> this.chips,
  })  : _compact = false,
        title = null,
        subtitleWidget = null,
        onBack = null,
        backIcon = AppIcons.chevronLeft,
        backTooltip = null,
        step = null,
        totalSteps = null,
        stepLabel = null;

  /// Compact (steps and other auth screens) variant.
  const AppAuthHeader.compact({
    super.key,
    required String this.title,
    this.subtitle,
    this.subtitleWidget,
    this.onBack,
    this.backIcon = AppIcons.chevronLeft,
    this.backTooltip,
    this.step,
    this.totalSteps,
    this.stepLabel,
  })  : _compact = true,
        headline = null,
        chips = null;

  final bool _compact;
  final String? headline;
  final String? title;
  final String? subtitle;

  /// Used instead of [subtitle] when it needs an icon (e.g. "Phone verified").
  final Widget? subtitleWidget;
  final List<AuthHeaderChip>? chips;

  /// Back action. Null ⇒ the button is shown dimmed and does nothing (a busy
  /// step). Leave it to the screen to pass its existing back behaviour.
  final VoidCallback? onBack;
  final IconData backIcon;
  final String? backTooltip;

  /// 1-based current step, and how many there are (draws [AppStepProgress]).
  final int? step;
  final int? totalSteps;

  /// The existing "n / total" counter shown beside the progress bar.
  final String? stepLabel;

  // Orange circle geometry (diameter, how far it sticks out right/top).
  static const double _loginOrange = 196, _loginRight = -60, _loginTop = -64;
  static const double _compactOrange = 156,
      _compactRight = -48,
      _compactTop = -52;

  /// How far (in px, from the right edge) the orange circle reaches in.
  static double accentReach(bool compact) =>
      compact ? _compactOrange + _compactRight : _loginOrange + _loginRight;

  /// How far (in px, from the top edge) the orange circle reaches down.
  static double accentDepth(bool compact) =>
      compact ? _compactOrange + _compactTop : _loginOrange + _loginTop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topInset = MediaQuery.paddingOf(context).top;
    final width = MediaQuery.sizeOf(context).width;
    // Text that sits in the circle's vertical range must stop before it.
    final reach = accentReach(_compact);
    final textMax = math.max(120.0, width - 24 - reach - 12);

    return Semantics(
      container: true,
      child: CustomPaint(
        foregroundPainter: _BottomEdgePainter(c.headerBorder, 36),
        child: ClipRRect(
          borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(36)),
          child: DecoratedBox(
            decoration: BoxDecoration(gradient: c.homeHeaderGradient),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                        child: _Decoration(compact: _compact, colors: c)),
                  ),
                ),
                Padding(
                  padding: _compact
                      ? EdgeInsets.fromLTRB(24, topInset + 14, 24, 22)
                      : EdgeInsets.fromLTRB(24, topInset + 20, 24, 30),
                  child: _compact
                      ? _compactBody(c, textMax)
                      : _loginBody(c, textMax),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginBody(AppColors c, double textMax) {
    final headStyle = AppTypography.heading(c).copyWith(
      fontSize: 32,
      color: c.headerText,
      letterSpacing: -0.32,
    );
    final subStyle = AppTypography.body(c).copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: c.authSub,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        UniflexWordmark(fontSize: 30, color: c.headerText),
        const SizedBox(height: 28),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: textMax),
          child: Semantics(
            header: true,
            child: Text(headline!, style: headStyle),
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Text(subtitle!, style: subStyle),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final chip in chips!) _GlassChip(chip: chip, colors: c)
          ],
        ),
      ],
    );
  }

  Widget _compactBody(AppColors c, double textMax) {
    final titleStyle = AppTypography.heading(c).copyWith(color: c.headerText);
    final subStyle = AppTypography.body(c).copyWith(
      fontSize: 15,
      fontWeight: FontWeight.w400,
      height: 1.4,
      color: c.authSub,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GlassBackButton(
          icon: backIcon,
          tooltip: backTooltip,
          onPressed: onBack,
          colors: c,
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: textMax),
          child:
              Semantics(header: true, child: Text(title!, style: titleStyle)),
        ),
        if (subtitleWidget != null || subtitle != null) ...[
          const SizedBox(height: 6),
          DefaultTextStyle(
            style: subStyle,
            child: subtitleWidget ?? Text(subtitle!, style: subStyle),
          ),
        ],
        if (step != null && totalSteps != null) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                  child: AppStepProgress(step: step!, totalSteps: totalSteps!)),
              if (stepLabel != null) ...[
                const SizedBox(width: 12),
                Text(
                  stepLabel!,
                  style:
                      AppTypography.sectionLabel(c).copyWith(color: c.authSub),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// n equal segments, 4 px high; completed and current ones in the header text
/// colour, upcoming ones white 22%. Driven by the existing step index.
class AppStepProgress extends StatelessWidget {
  const AppStepProgress(
      {super.key, required this.step, required this.totalSteps});

  final int step;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Step $step of $totalSteps',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 1; i <= totalSteps; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color:
                        i <= step ? c.headerText : AppColors.authProgressTrack,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip({required this.chip, required this.colors});
  final AuthHeaderChip chip;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.fromLTRB(10, 0, 13, 0),
      decoration: BoxDecoration(
        color: colors.headerPanelFill,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: colors.headerPanelBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(chip.icon, size: 16, color: colors.headerText),
          const SizedBox(width: 6),
          Text(
            chip.label,
            style: AppTypography.sectionLabel(colors).copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
              color: colors.headerText,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton({
    required this.icon,
    required this.onPressed,
    required this.colors,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final AppColors colors;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.iconButton);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: tooltip ?? 'Back',
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Material(
              color: colors.headerPanelFill,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: colors.headerPanelBorder),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onPressed,
                child: Center(
                  child: Icon(icon,
                      size: AppIconSize.regular, color: colors.headerText),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Decoration extends StatelessWidget {
  const _Decoration({required this.compact, required this.colors});
  final bool compact;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final size =
        compact ? AppAuthHeader._compactOrange : AppAuthHeader._loginOrange;
    final right =
        compact ? AppAuthHeader._compactRight : AppAuthHeader._loginRight;
    final top = compact ? AppAuthHeader._compactTop : AppAuthHeader._loginTop;
    final halo1 = compact ? 14.0 : 16.0;
    final halo2 = compact ? 30.0 : 34.0;

    Widget disc(double d, double r, double t, Decoration deco) => Positioned(
          right: r,
          top: t,
          width: d,
          height: d,
          child: DecoratedBox(decoration: deco),
        );

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        // Plain white 5% disc, bottom-left, partly off-screen.
        const Positioned(
          left: -70,
          bottom: -90,
          width: 210,
          height: 210,
          child: DecoratedBox(
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: AppColors.authDisc),
          ),
        ),
        // Halo rings (outer first), then the orange circle.
        disc(
            size + halo2 * 2,
            right - halo2,
            top - halo2,
            const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.authHaloOuter)),
        disc(
            size + halo1 * 2,
            right - halo1,
            top - halo1,
            const BoxDecoration(
                shape: BoxShape.circle, color: AppColors.authHaloInner)),
        disc(size, right, top,
            BoxDecoration(shape: BoxShape.circle, gradient: colors.authAccent)),
      ],
    );
  }
}

/// 1 px line along the bottom edge and the two rounded bottom corners only.
class _BottomEdgePainter extends CustomPainter {
  _BottomEdgePainter(this.color, this.radius);
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const o = 0.5;
    final r = radius;
    final path = Path()
      ..moveTo(o, size.height - r)
      ..arcToPoint(Offset(r, size.height - o), radius: Radius.circular(r - o))
      ..lineTo(size.width - r, size.height - o)
      ..arcToPoint(Offset(size.width - o, size.height - r),
          radius: Radius.circular(r - o));
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_BottomEdgePainter old) =>
      old.color != color || old.radius != radius;
}
