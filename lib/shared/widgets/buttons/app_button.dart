import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'tap_guard.dart';

// The dialog lives in this library (as a `part`) ONLY so it can reach the
// private danger constructor below. That is what makes a solid-red button
// impossible to build anywhere else in the app.
part '../dialogs/app_dialog.dart';

/// The visible kinds of [AppButton]. There is deliberately no `danger` here:
/// solid red exists only inside [AppDialog].
enum AppButtonVariant {
  /// Brand fill, onBrand label. The one main action on a screen.
  primary,

  /// Transparent, 1px strong border, primary-text label.
  secondary,

  /// No fill, no border, brandText label (links, "Skip").
  text,

  /// Transparent, 1px strong border, red label. **Every Cancel uses this.**
  quietDanger,

  /// Raised-surface fill, tertiary label. Also what `primary` turns into when
  /// `onPressed` is null.
  disabled,
}

enum AppButtonSize {
  /// 52 high, 16/600 label.
  medium,

  /// 40 high, 14/600 label.
  small,
}

enum _Kind { primary, secondary, text, quietDanger, disabled, danger }

/// THE button. No shadow, no elevation, no gradient. Always guarded against
/// double taps (see [TapGuard]).
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.medium,
    this.icon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = true,
  }) : _kind = null;

  /// Solid red + white label. Private on purpose — only [AppDialog] uses it.
  const AppButton._dialogDanger({
    required this.label,
    required this.onPressed,
  })  : variant = AppButtonVariant.primary,
        size = AppButtonSize.medium,
        icon = null,
        trailingIcon = null,
        isLoading = false,
        expand = true,
        _kind = _Kind.danger,
        super(key: null);

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;

  /// Optional 20px leading icon.
  final IconData? icon;

  /// Optional trailing icon (e.g. a chevron on "Track").
  final IconData? trailingIcon;

  /// Shows a small spinner in place of the label, keeping the same width.
  final bool isLoading;

  /// Full width (default) or hug the content.
  final bool expand;

  final _Kind? _kind;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  final TapGuard _guard = TapGuard();

  _Kind get _kind {
    final forced = widget._kind;
    if (forced != null) return forced;
    final disabledLook = widget.onPressed == null && !widget.isLoading;
    return switch (widget.variant) {
      AppButtonVariant.primary => disabledLook ? _Kind.disabled : _Kind.primary,
      AppButtonVariant.secondary => _Kind.secondary,
      AppButtonVariant.text => _Kind.text,
      AppButtonVariant.quietDanger => _Kind.quietDanger,
      AppButtonVariant.disabled => _Kind.disabled,
    };
  }

  void _tap() {
    final cb = widget.onPressed;
    if (cb == null || widget.isLoading) return;
    _guard.run(cb);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = _kind;
    final small = widget.size == AppButtonSize.small;
    final enabled =
        widget.onPressed != null && !widget.isLoading && kind != _Kind.disabled;

    final (Color fill, Color label, BorderSide side) = switch (kind) {
      _Kind.primary => (c.brand, c.onBrand, BorderSide.none),
      _Kind.danger => (c.dangerSolid, c.onDangerSolid, BorderSide.none),
      _Kind.secondary => (
          Colors.transparent,
          widget.onPressed == null ? c.textTertiary : c.textPrimary,
          BorderSide(color: c.borderStrong)
        ),
      _Kind.quietDanger => (
          Colors.transparent,
          widget.onPressed == null ? c.textTertiary : c.dangerText,
          BorderSide(color: c.borderStrong)
        ),
      _Kind.text => (
          Colors.transparent,
          widget.onPressed == null ? c.textTertiary : c.brandText,
          BorderSide.none
        ),
      _Kind.disabled => (c.surfaceRaised, c.textTertiary, BorderSide.none),
    };

    final style =
        small ? AppTypography.buttonSmall(label) : AppTypography.button(label);
    final height =
        small ? AppSpacing.controlHeightSmall : AppSpacing.controlHeight;
    final radius =
        BorderRadius.circular(small ? AppRadius.buttonSmall : AppRadius.button);

    final content = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: AppIconSize.inButton, color: label),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Text(
            widget.label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (widget.trailingIcon != null) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(widget.trailingIcon, size: AppIconSize.inButton, color: label),
        ],
      ],
    );

    // Spinner sits on top of the (invisible) label so the width never changes.
    final body = Stack(
      alignment: Alignment.center,
      children: [
        Opacity(opacity: widget.isLoading ? 0 : 1, child: content),
        if (widget.isLoading)
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: label),
          ),
      ],
    );

    final button = Material(
      color: fill,
      shape: RoundedRectangleBorder(borderRadius: radius, side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? _tap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: height, minWidth: 0),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? AppSpacing.md : AppSpacing.lg,
              vertical: 0,
            ),
            child: Center(widthFactor: widget.expand ? null : 1, child: body),
          ),
        ),
      ),
    );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      onTap: enabled ? _tap : null,
      child: widget.expand
          ? SizedBox(width: double.infinity, height: height, child: button)
          : SizedBox(height: height, child: button),
    );
  }
}
