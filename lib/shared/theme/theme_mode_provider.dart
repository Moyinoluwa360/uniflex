import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Saves the Preferences → Appearance choice on this phone, so it survives
/// the app being closed (iOS often closes backgrounded apps; before this the
/// choice was memory-only and silently fell back to "System default").
abstract final class ThemeModeStore {
  static const _key = 'uniflex_theme_mode';

  /// What the app starts with; set by [load] in `main()` before `runApp`,
  /// so the first frame already uses the saved theme (no flash).
  static ThemeMode initial = ThemeMode.system;

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      initial = _parse(prefs.getString(_key));
    } catch (_) {
      initial = ThemeMode.system;
    }
  }

  static Future<void> save(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {
      // Not fatal: the choice still applies for this session.
    }
  }

  static ThemeMode _parse(String? raw) => switch (raw) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
}

/// Current [ThemeMode] for the whole app (Preferences → Appearance). Starts
/// from the saved choice; `UniflexApp` saves every change.
final themeModeProvider =
    StateProvider<ThemeMode>((ref) => ThemeModeStore.initial);
