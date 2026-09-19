import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../app_bar/uniflex_app_bar.dart';
import '../auth/logout_button.dart';

/// Used by each role shell's tab screens until real feature screens are
/// built in later phases. Confirms which shell/role is currently loaded.
/// [showLogout] puts a real sign-out action on the screen — used by each
/// shell's Profile tab; a full Profile screen replaces this in a later
/// phase.
class RolePlaceholderScreen extends StatelessWidget {
  const RolePlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.showLogout = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final bool showLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UniflexAppBar(title: title),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
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
            if (showLogout) ...[
              const SizedBox(height: AppSpacing.xxl),
              const LogoutButton(),
            ],
          ],
        ),
      ),
    );
  }
}
