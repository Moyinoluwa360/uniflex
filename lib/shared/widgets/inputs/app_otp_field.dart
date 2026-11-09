import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import 'app_text_field.dart';

/// One box per digit, painted from ONE hidden text field (UI Polish 3).
///
/// It is a display layer: the real input is a single [AppTextField] that is
/// laid over the boxes with transparent text, so typing, pasting, backspace and
/// the iOS one-time-code suggestion all behave like a plain code field, and the
/// screen keeps reading/clearing the same [controller]. The caret is forced to
/// the end, so tapping a box can never insert a digit in the middle.
///
/// Box: height 60, radius 14, fill `surface`, 1 px `border`; the active box
/// has a `brand` border and a blinking caret; a wrong code ([errorText] set)
/// turns every border `dangerText` and shows the message below.
class AppOtpField extends StatefulWidget {
  const AppOtpField({
    super.key,
    required this.controller,
    this.length = 6,
    this.errorText,
    this.onChanged,
    this.onCompleted,
    this.autofocus = false,
    this.enabled = true,
    this.focusNode,
  });

  final TextEditingController controller;

  /// Number of boxes (and the maximum code length).
  final int length;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  /// Called when the code reaches [length] digits through typing or paste.
  final ValueChanged<String>? onCompleted;
  final bool autofocus;
  final bool enabled;
  final FocusNode? focusNode;

  @override
  State<AppOtpField> createState() => _AppOtpFieldState();
}

class _AppOtpFieldState extends State<AppOtpField>
    with SingleTickerProviderStateMixin {
  FocusNode? _ownNode;
  late final AnimationController _blink = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  FocusNode get _node => widget.focusNode ?? (_ownNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    _node.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(AppOtpField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    (widget.focusNode ?? _ownNode)?.removeListener(_rebuild);
    _ownNode?.dispose();
    _blink.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onText() {
    final c = widget.controller;
    final end = c.text.length;
    // Keep the caret at the end (a tap on a box must not insert mid-code).
    if (!c.selection.isCollapsed || c.selection.baseOffset != end) {
      c.selection = TextSelection.collapsed(offset: end);
    }
    _rebuild();
  }

  void _changed(String v) {
    widget.onChanged?.call(v);
    if (v.length == widget.length) widget.onCompleted?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = widget.controller.text;
    final hasError = widget.errorText != null;
    final focused = _node.hasFocus && widget.enabled;
    final active = text.length.clamp(0, widget.length - 1);

    final digitStyle = AppTypography.tabular(
      AppTypography.heading(c).copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        letterSpacing: 0,
        height: 1.1,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(builder: (context, cons) {
          final gap =
              (cons.maxWidth - 5 * 10) / widget.length < 44 ? 8.0 : 10.0;
          return Semantics(
            label: 'Verification code, ${widget.length} digits',
            textField: true,
            child: Stack(
              children: [
                ExcludeSemantics(
                  child: IgnorePointer(
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.length; i++) ...[
                          if (i > 0) SizedBox(width: gap),
                          Expanded(
                            child: _Box(
                              key: ValueKey('otp-box-$i'),
                              digit: i < text.length ? text[i] : '',
                              isActive: focused && i == active,
                              showCaret:
                                  focused && i == active && i >= text.length,
                              hasError: hasError,
                              blink: _blink,
                              digitStyle: digitStyle,
                              colors: c,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // The real input, invisible, on top so every tap focuses it.
                Positioned.fill(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      textSelectionTheme: const TextSelectionThemeData(
                        cursorColor: Colors.transparent,
                        selectionColor: Colors.transparent,
                        selectionHandleColor: Colors.transparent,
                      ),
                    ),
                    child: AppTextField(
                      key: const ValueKey('otp-input'),
                      controller: widget.controller,
                      focusNode: _node,
                      enabled: widget.enabled,
                      autofocus: widget.autofocus,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      showCursor: false,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(widget.length),
                      ],
                      onChanged: _changed,
                      style: const TextStyle(color: Colors.transparent),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                        constraints: BoxConstraints(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        if (hasError) ...[
          const SizedBox(height: AppSpacing.sm),
          AppFieldErrorRow(widget.errorText!),
        ],
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    super.key,
    required this.digit,
    required this.isActive,
    required this.showCaret,
    required this.hasError,
    required this.blink,
    required this.digitStyle,
    required this.colors,
  });

  final String digit;
  final bool isActive;
  final bool showCaret;
  final bool hasError;
  final Animation<double> blink;
  final TextStyle digitStyle;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final Color border =
        hasError ? c.dangerText : (isActive ? c.brand : c.border);
    return Container(
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.input),
        border:
            Border.all(color: border, width: (isActive || hasError) ? 1.5 : 1),
        boxShadow: c.cardShadow,
      ),
      child: showCaret
          ? FadeTransition(
              opacity: blink.drive(
                TweenSequence<double>([
                  TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
                  TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
                ]),
              ),
              child: Container(
                key: const ValueKey('otp-caret'),
                width: 2,
                height: 26,
                color: c.brand,
              ),
            )
          : Text(digit, style: digitStyle.copyWith(color: c.textPrimary)),
    );
  }
}
