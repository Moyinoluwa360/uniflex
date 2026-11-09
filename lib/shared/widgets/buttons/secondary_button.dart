import 'package:flutter/material.dart';

import 'app_button.dart';

/// Compatibility wrapper: an outlined, neutral [AppButton] (secondary). New
/// code: use [AppButton] directly (and `quietDanger` for Cancel).
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      variant: AppButtonVariant.secondary,
      icon: icon,
      expand: expand,
    );
  }
}
