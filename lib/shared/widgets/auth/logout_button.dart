import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../buttons/secondary_button.dart';

/// Signs the current user out. [AuthGate] watches auth state, so once
/// [AuthService.signOut] completes it reacts on its own and swaps the
/// whole app back to the Login screen — this button does not navigate
/// anywhere itself.
///
/// Phase 1 only needs a button on each shell's placeholder screen; a real
/// Profile screen with this same action comes in a later phase.
class LogoutButton extends ConsumerStatefulWidget {
  const LogoutButton({super.key});

  @override
  ConsumerState<LogoutButton> createState() => _LogoutButtonState();
}

class _LogoutButtonState extends ConsumerState<LogoutButton> {
  bool _isLoading = false;

  Future<void> _signOut() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authServiceProvider).signOut();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not log out. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: _isLoading ? 'Logging out…' : 'Log out',
      icon: Icons.logout,
      onPressed: _isLoading ? null : _signOut,
    );
  }
}
