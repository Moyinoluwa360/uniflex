import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'shared/router/role_router.dart';
import 'shared/theme/app_theme.dart';
import 'shared/theme/theme_mode_provider.dart';

/// Root widget. Everything role-specific happens inside [RoleRouter] —
/// this widget only owns the app-wide theme and MaterialApp shell.
class UniflexApp extends ConsumerWidget {
  const UniflexApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'Uniflex',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const RoleRouter(),
    );
  }
}
