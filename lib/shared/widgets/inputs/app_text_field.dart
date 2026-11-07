import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return TextFormField(
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
      style: w.style,
      textAlign: w.textAlign,
      textCapitalization: w.textCapitalization,
      autofocus: w.autofocus,
      onFieldSubmitted: w.onSubmitted,
      onTapUpOutside: _onTapUpOutside,
      decoration: w.decoration ??
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
