import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth/session_provider.dart';
import '../services/auth/user_role.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_mode_provider.dart';
import '../widgets/buttons/primary_button.dart';
import '../widgets/wordmark/uniflex_wordmark.dart';

/// PHASE 0 PLACEHOLDER — not a real screen, not the onboarding flow.
///
/// There is no auth yet, so this exists purely to let [RoleRouter] have
/// something to fall back to and to prove, by hand, that setting
/// [currentUserRoleProvider] correctly routes to each of the three shells.
/// Phase 1 (Onboarding & Auth) deletes this screen and replaces it with
/// real sign-in; nothing else in the router needs to change when that
/// happens.
class MockRoleSelectScreen extends ConsumerWidget {
  const MockRoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Toggle light / dark mode',
                  icon: Icon(
                    themeMode == ThemeMode.dark
                        ? Icons.dark_mode
                        : Icons.light_mode,
                  ),
                  onPressed: () {
                    ref.read(themeModeProvider.notifier).state =
                        themeMode == ThemeMode.dark
                        ? ThemeMode.light
                        : ThemeMode.dark;
                  },
                ),
              ),
              const Spacer(),
              const Center(child: UniflexWordmark(fontSize: 40)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Phase 0 — mock role select\n(replaced by real sign-in in Phase 1)',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: 'Continue as Student',
                onPressed: () => _selectRole(ref, UserRole.student),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Continue as Rider',
                onPressed: () => _selectRole(ref, UserRole.rider),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Continue as Admin',
                onPressed: () => _selectRole(ref, UserRole.admin),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }

  void _selectRole(WidgetRef ref, UserRole role) {
    ref.read(currentUserRoleProvider.notifier).state = role;
  }
}
