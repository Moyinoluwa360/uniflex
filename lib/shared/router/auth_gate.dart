import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/screens/complete_profile_screen.dart';
import '../auth/screens/login_screen.dart';
import '../services/auth/auth_providers.dart';
import '../theme/app_spacing.dart';
import 'role_router.dart';
import 'splash_screen.dart';

/// The single entry point that decides what a person sees on launch (and
/// reacts live to sign-in/sign-out afterwards):
///
///   1. [SplashScreen] plays its entrance animation for a minimum
///      stretch while [currentProfileProvider] resolves whether there's
///      a valid, restored session.
///   2. No session → [LoginScreen] (which itself links to
///      [CreateAccountScreen] for Student self-signup — the only signup
///      path that exists).
///   3. Session, but the profile row's `onboarding_complete` is still
///      false → [CompleteProfileScreen] (Step Two), so a student who
///      closed the app mid-onboarding resumes exactly there instead of
///      being sent back through Step One.
///   4. Session with a completed profile → [RoleRouter], which loads the
///      shell matching `profiles.role` (Student/Rider/Admin).
///
/// Nothing under lib/shared/auth/ or lib/shared/router/role_router.dart
/// navigates the app directly on success — they mutate auth state (sign
/// in/out, complete onboarding) and this widget, which watches
/// [currentProfileProvider], reacts on its own. That keeps "what am I
/// looking at" always a pure function of the signed-in session instead
/// of scattered imperative navigation calls that could drift out of
/// sync with it.
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  bool _minimumSplashElapsed = false;

  @override
  void initState() {
    super.initState();
    // Splash must show for a minimum stretch even when the session
    // resolves instantly (already-restored, cached session) — it should
    // never flash for a single frame.
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _minimumSplashElapsed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentProfileProvider);

    if (!_minimumSplashElapsed || profileAsync.isLoading) {
      return const SplashScreen();
    }

    final profile = profileAsync.valueOrNull;
    if (profileAsync.hasError || profile == null) {
      return const LoginScreen();
    }
    if (!profile.onboardingComplete) {
      return const CompleteProfileScreen();
    }
    if (!profile.isActive) {
      // Post-testing fixes, Section 7: an admin-removed/deactivated
      // account (currently only riders) never reaches a role shell.
      // Sign out as a side effect so the next currentProfileProvider
      // resolution sees no session and swaps to LoginScreen on its own.
      return const _AccountDeactivatedScreen();
    }
    return RoleRouter(role: profile.role);
  }
}

class _AccountDeactivatedScreen extends ConsumerWidget {
  const _AccountDeactivatedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.block_outlined,
                    size: 36,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Account deactivated',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your account has been deactivated by an admin. '
                'Contact Uniflex support if you think this is a mistake.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => ref.read(authServiceProvider).signOut(),
                child: const Text('Back to Login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
