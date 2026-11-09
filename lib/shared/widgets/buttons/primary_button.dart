import 'package:flutter/material.dart';

import 'app_button.dart';

/// Compatibility wrapper: the CTA button used by ~35 call sites. It now just
/// renders an [AppButton] (primary), so it picks up the new look and the
/// double-tap guard without any call site changing. New code: use
/// [AppButton] directly.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      icon: icon,
      expand: expand,
    );
  }
}
