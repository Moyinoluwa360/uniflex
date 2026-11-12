// Preferences → Appearance must survive the app being closed.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniflex/shared/theme/theme_mode_provider.dart';

void main() {
  test('nothing saved → System default', () async {
    SharedPreferences.setMockInitialValues({});
    await ThemeModeStore.load();
    expect(ThemeModeStore.initial, ThemeMode.system);
  });

  for (final mode in ThemeMode.values) {
    test('${mode.name} is saved and comes back after a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await ThemeModeStore.save(mode);
      ThemeModeStore.initial = ThemeMode.system; // "restart"
      await ThemeModeStore.load();
      expect(ThemeModeStore.initial, mode);
    });
  }
}
