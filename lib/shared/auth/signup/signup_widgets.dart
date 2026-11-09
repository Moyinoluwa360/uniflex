import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../widgets/notice/app_inline_notice.dart';

/// The red message box used by every sign-up step (same look the old
/// screens had, now in one place).
class SignupErrorBanner extends StatelessWidget {
  const SignupErrorBanner(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppInlineNotice(isError: true, text: text),
    );
  }
}
