import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Current [ThemeMode] for the whole app. Defaults to following the
/// device setting; the Phase 0 mock role-select screen exposes a manual
/// toggle purely so light/dark mode can be verified without changing OS
/// settings.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
