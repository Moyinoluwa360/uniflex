import 'package:flutter/material.dart';

/// Standard text input. Styling comes entirely from
/// `ThemeData.inputDecorationTheme` (see AppTheme) — this widget just
/// gives screens a consistent, typed API instead of configuring
/// [TextFormField] by hand everywhere.
class AppTextField extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      onChanged: onChanged,
      textInputAction: textInputAction,
      validator: validator,
      autovalidateMode: autovalidateMode,
      maxLength: maxLength,
      maxLines: obscureText ? 1 : maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
