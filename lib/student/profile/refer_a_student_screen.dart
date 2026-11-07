import 'package:flutter/material.dart';

import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/widgets/app_bar/uniflex_app_bar.dart';
import '../../shared/widgets/buttons/primary_button.dart';
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
    return Scaffold(
      appBar: const UniflexAppBar(title: 'Refer a student'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            const CircleAvatar(
              radius: 36,
              backgroundColor: AppColors.emerald,
              child: Icon(Icons.people, color: AppColors.pureWhite, size: 36),
            ),
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
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(
              label: 'Contact support',
              icon: Icons.support_agent_outlined,
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
