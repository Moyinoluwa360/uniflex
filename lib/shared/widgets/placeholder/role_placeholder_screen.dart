import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/session_provider.dart';
import '../../theme/app_spacing.dart';
import '../app_bar/uniflex_app_bar.dart';
import '../buttons/secondary_button.dart';

/// PHASE 0 PLACEHOLDER — used by each role shell's tab screens until real
/// feature screens are built in later phases. Confirms which shell/role is
/// currently loaded and gives a way back to [MockRoleSelectScreen] for
/// testing the router without a real sign-out flow.
class RolePlaceholderScreen extends ConsumerWidget {
  const RolePlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: UniflexAppBar(title: title),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            SecondaryButton(
              label: 'Switch role (dev)',
              icon: Icons.swap_horiz,
              onPressed: () {
                ref.read(currentUserRoleProvider.notifier).state = null;
              },
            ),
          ],
        ),
      ),
    );
  }
}
