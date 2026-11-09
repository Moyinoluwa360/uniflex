import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_icons.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_typography.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/app_button.dart';
import '../support/support_options_screen.dart';

/// "Refer a student" — deliberately simple.
///
/// Referral codes are handed out by Admin, so a student never sees a code of
/// their own here, nor any amounts, counts or rankings. This screen only
/// tells them to ask support for one and opens Help & Support.
class ReferAStudentScreen extends StatelessWidget {
  const ReferAStudentScreen({super.key, this.openSupport});

  /// Replaced in tests; by default opens Help & Support.
  final VoidCallback? openSupport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Refer a student'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(AppIcons.group, color: c.brandText, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Want to refer a student?',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Contact Admin to get a referral code.',
              key: const ValueKey('refer-contact-admin'),
              style: AppTypography.meta(c),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            AppButton(
              label: 'Contact support',
              icon: AppIcons.chat,
              onPressed: openSupport ??
                  () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SupportOptionsScreen(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
