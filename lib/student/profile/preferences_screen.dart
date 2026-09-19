import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/theme_mode_provider.dart';

/// Preferences screen — exposes the app-wide theme toggle.
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenGutter),
        children: [
          Text('Appearance', style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Card(
            child: Column(
              children: ThemeMode.values.map((mode) {
                final label = switch (mode) {
                  ThemeMode.system => 'System default',
                  ThemeMode.light => 'Light',
                  ThemeMode.dark => 'Dark',
                };
                final icon = switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                };
                final isSelected = themeMode == mode;
                return ListTile(
                  leading: Icon(icon,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : null),
                  title: Text(label),
                  trailing: isSelected
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary)
                      : const Icon(Icons.radio_button_unchecked),
                  onTap: () =>
                      ref.read(themeModeProvider.notifier).state = mode,
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
