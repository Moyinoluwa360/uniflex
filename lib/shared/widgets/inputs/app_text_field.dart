import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

/// Standard text input — THE text field of the app. Styling comes entirely
/// from `ThemeData.inputDecorationTheme` (see AppTheme); this widget gives
/// screens a consistent, typed API instead of configuring [TextFormField]
/// by hand everywhere.
///
/// **Pack 6 — "stuck selection highlight" fix.** Flutter's own default is
/// that on a phone, touching outside a text field does NOT take focus away
/// from it (that only happens on desktop/web). A field that keeps focus keeps
/// drawing its selection highlight, handles and toolbar — so after selecting
/// text and tapping elsewhere or scrolling, the highlight looked frozen on
/// screen. Every [AppTextField] therefore:
///  * gives up focus when a tap ends outside it (taps on buttons still work:
///    it reacts on pointer-UP, after the button has already fired), and
///  * collapses any highlighted range the moment it loses focus, however it
///    lost it (tap outside, scroll-drag dismissing the keyboard, route
///    closing, programmatic unfocus), so no selection is left in the
///    controller either.
/// The scroll-drag and background-tap parts live at the app root, see
/// `keyboard_dismiss.dart`.
///
/// When [decoration] is given it is used as-is (for the few fields that need
/// their own prefix, border or counter); otherwise it is built from
/// [label]/[hint]/etc.
///
/// **`large` (UI Polish 3, auth + sign-up):** a 56 px box (radius 14, fill
/// `surface`, 1 px `border`, light theme adds the card shadow). 22 px leading
/// icon (turns `brandText` while focused), 15.5/500 text. The field's [label]
/// is shown inside the box as the placeholder, and a separate [hint] (when a
/// label exists) becomes the helper line under it — every existing string is
/// still on screen, only its place changed. Errors show 6 px below with a
/// 14 px alert icon, never a solid red box. Behaviour, controllers,
/// validators, keyboard types and obscure logic are untouched.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.suffixIcon,
    this.enabled = true,
    this.onChanged,
    this.textInputAction,
    this.validator,
    this.autovalidateMode,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.inputFormatters,
    this.decoration,
    this.style,
    this.textAlign = TextAlign.start,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.onSubmitted,
    this.focusNode,
    this.large = false,
    this.helperText,
    this.readOnly = false,
    this.onTap,
    this.autofillHints,
    this.showCursor,
    this.enableInteractiveSelection,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;
  final AutovalidateMode? autovalidateMode;
  final int? maxLength;
  final int? maxLines;
  final int? minLines;
  final List<TextInputFormatter>? inputFormatters;

  /// Full control of the decoration (overrides label/hint/errorText/icons).
  final InputDecoration? decoration;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextCapitalization textCapitalization;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// The 56 px auth / sign-up look (see the class doc).
  final bool large;

  /// Helper line under a [large] field. Defaults to [hint] when a [label]
  /// is also given.
  final String? helperText;
  final bool readOnly;
  final VoidCallback? onTap;
  final Iterable<String>? autofillHints;
  final bool? showCursor;
  final bool? enableInteractiveSelection;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  FocusNode? _ownNode;
  TextEditingController? _ownController;

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());
  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(AppTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownNode)?.removeListener(_onFocusChanged);
      _node.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    (widget.focusNode ?? _ownNode)?.removeListener(_onFocusChanged);
    _ownNode?.dispose();
    _ownController?.dispose();
    super.dispose();
  }

  /// Focus gone ⇒ nothing may stay highlighted.
  void _onFocusChanged() {
    if (widget.large && mounted) setState(() {}); // icon colour follows focus
    if (_node.hasFocus) return;
    final c = _controller;
    final sel = c.selection;
    if (sel.isValid && !sel.isCollapsed) {
      c.selection = TextSelection.collapsed(offset: sel.extentOffset);
    }
  }

  void _onTapUpOutside(PointerUpEvent _) {
    if (_node.hasFocus) _node.unfocus();
  }

  Widget _errorRow(BuildContext context, String text) => AppFieldErrorRow(text);

  InputDecoration _largeDecoration(BuildContext context) {
    final w = widget;
    final locked = !w.enabled || w.readOnly;
    return appLargeInputDecoration(
      context,
      placeholder: w.label ?? w.hint,
      helper: w.helperText ?? (w.label != null ? w.hint : null),
      errorText: w.errorText,
      leadingIcon: w.prefixIcon,
      trailing: w.suffixIcon,
      focused: _node.hasFocus && !locked,
      locked: locked,
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final large = w.large && w.decoration == null;
    final c = context.colors;
    return TextFormField(
      readOnly: w.readOnly,
      onTap: w.onTap,
      autofillHints: w.autofillHints,
      showCursor: w.showCursor,
      enableInteractiveSelection: w.enableInteractiveSelection,
      errorBuilder: large ? _errorRow : null,
      controller: _controller,
      focusNode: _node,
      obscureText: w.obscureText,
      keyboardType: w.keyboardType,
      enabled: w.enabled,
      onChanged: w.onChanged,
      textInputAction: w.textInputAction,
      validator: w.validator,
      autovalidateMode: w.autovalidateMode,
      maxLength: w.maxLength,
      maxLines: w.obscureText ? 1 : w.maxLines,
      minLines: w.obscureText ? null : w.minLines,
      inputFormatters: w.inputFormatters,
      style: w.style ??
          (large
              ? AppTypography.body(c).copyWith(
                  fontSize: 15.5,
                  color: (!w.enabled || w.readOnly)
                      ? c.textSecondary
                      : c.textPrimary,
                )
              : null),
      textAlign: w.textAlign,
      textCapitalization: w.textCapitalization,
      autofocus: w.autofocus,
      onFieldSubmitted: w.onSubmitted,
      onTapUpOutside: _onTapUpOutside,
      decoration: w.decoration ??
          (large ? _largeDecoration(context) : null) ??
          InputDecoration(
            labelText: w.label,
            hintText: w.hint,
            errorText: w.errorText,
            prefixIcon: w.prefixIcon != null ? Icon(w.prefixIcon) : null,
            suffixIcon: w.suffixIcon,
          ),
    );
  }
}

/// An [OutlineInputBorder] that also paints the light theme's card shadow
/// outside the box (nothing inside it, nothing under the helper/error line).
class _ShadowedOutline extends OutlineInputBorder {
  const _ShadowedOutline({
    required this.shadows,
    super.borderRadius,
    super.borderSide,
  });

  final List<BoxShadow> shadows;

  @override
  OutlineInputBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) =>
      _ShadowedOutline(
        shadows: shadows,
        borderSide: borderSide ?? this.borderSide,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    if (shadows.isNotEmpty) {
      final rrect = borderRadius.toRRect(rect);
      final outside = Path.combine(
        PathOperation.difference,
        Path()..addRect(rect.inflate(24)),
        Path()..addRRect(rrect),
      );
      canvas.save();
      canvas.clipPath(outside);
      for (final s in shadows) {
        canvas.drawRRect(rrect.shift(s.offset), s.toPaint());
      }
      canvas.restore();
    }
    super.paint(canvas, rect,
        gapStart: gapStart,
        gapExtent: gapExtent,
        gapPercentage: gapPercentage,
        textDirection: textDirection);
  }
}

/// The error line of a large field: 14 px alert icon + 12.5/500 `dangerText`,
/// indented 4. (Never a solid red box.)
class AppFieldErrorRow extends StatelessWidget {
  const AppFieldErrorRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(AppIcons.error, size: 14, color: c.dangerText),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.caption(c).copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: c.dangerText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The decoration of the 56 px "large" field. Shared by [AppTextField] and
/// the picker/dropdown boxes so every input on the auth screens matches.
InputDecoration appLargeInputDecoration(
  BuildContext context, {
  String? placeholder,
  String? helper,
  String? errorText,
  IconData? leadingIcon,
  Widget? trailing,
  bool focused = false,
  bool locked = false,
}) {
  final c = context.colors;
  final hasIcon = leadingIcon != null;

  OutlineInputBorder border(Color color, [double width = 1]) =>
      _ShadowedOutline(
        shadows: c.cardShadow,
        borderRadius: BorderRadius.circular(AppRadius.input),
        borderSide: BorderSide(color: color, width: width),
      );

  return InputDecoration(
    filled: true,
    fillColor: locked ? c.surfaceRaised : c.surface,
    constraints: const BoxConstraints(minHeight: 56),
    isDense: false,
    contentPadding: EdgeInsetsDirectional.only(
        start: hasIcon ? 0 : 16, end: 16, top: 16, bottom: 16),
    hintText: placeholder,
    hintStyle:
        AppTypography.body(c).copyWith(fontSize: 15.5, color: c.textTertiary),
    hintMaxLines: 1,
    counterText: '',
    prefixIcon: hasIcon
        ? Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, end: 12),
            child: Icon(
              leadingIcon,
              size: 22,
              color: focused ? c.brandText : c.textSecondary,
            ),
          )
        : null,
    prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    suffixIcon: trailing ??
        (locked
            ? Padding(
                padding: const EdgeInsetsDirectional.only(end: 14),
                child: Icon(AppIcons.lock, size: 18, color: c.textTertiary),
              )
            : null),
    suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    helper: helper == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(left: 4, top: 2),
            child: Text(helper, style: AppTypography.caption(c)),
          ),
    error: errorText == null ? null : AppFieldErrorRow(errorText),
    errorMaxLines: 3,
    border: border(c.border),
    enabledBorder: border(c.border),
    disabledBorder: border(c.border),
    focusedBorder: border(c.brand, 1.5),
    errorBorder: border(c.dangerText),
    focusedErrorBorder: border(c.dangerText, 1.5),
  );
}
