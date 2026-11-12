import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared/theme/theme_mode_provider.dart';

/// Wraps the app in a [ProviderScope] that is thrown away and rebuilt
/// whenever a signed-in user signs out or a different account signs in.
///
/// Why: data providers (wallet balance, orders, notifications, support chat,
/// gifts, rider jobs, …) cache the first value they load for the life of the
/// app. Without this, after logging out of account A and into account B on
/// the same phone, B could see A's balance until the app was restarted.
/// A fresh scope is exactly what a cold start gives: nothing from the
/// previous person survives in memory.
///
/// Going from "nobody" to a user (login, sign-up, password-reset sessions)
/// does NOT rebuild — nothing user-specific is cached while signed out, and
/// rebuilding there would throw people out of the sign-up / reset screens.
///
/// The light/dark choice is carried over; [onUserChanged] runs before the
/// rebuild (used to delete the previous person's saved cart).
class UserSessionScope extends StatefulWidget {
  const UserSessionScope({
    super.key,
    required this.initialUserId,
    required this.userIdChanges,
    required this.child,
    this.onUserChanged,
  });

  /// The user signed in when the app starts (null = nobody).
  final String? initialUserId;

  /// Emits the signed-in user id (or null) on every auth change.
  final Stream<String?> userIdChanges;

  final Widget child;

  /// Called when a signed-in user signs out or is replaced by another one.
  final Future<void> Function()? onUserChanged;

  @override
  State<UserSessionScope> createState() => _UserSessionScopeState();
}

class _UserSessionScopeState extends State<UserSessionScope> {
  late String? _userId = widget.initialUserId;
  int _generation = 0;
  ThemeMode _themeMode = ThemeModeStore.initial;
  ProviderContainer? _container;
  StreamSubscription<String?>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.userIdChanges.listen(_onUser);
  }

  Future<void> _onUser(String? id) async {
    final previous = _userId;
    _userId = id;
    if (previous == null || previous == id) return;
    await widget.onUserChanged?.call();
    if (!mounted) return;
    // Carry the light/dark choice into the fresh scope.
    _themeMode = _container?.read(themeModeProvider) ?? _themeMode;
    setState(() => _generation++);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_generation),
      overrides: [themeModeProvider.overrideWith((ref) => _themeMode)],
      child: Builder(
        builder: (context) {
          _container = ProviderScope.containerOf(context, listen: false);
          return widget.child;
        },
      ),
    );
  }
}
