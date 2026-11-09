import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The "no hard-coded colours" guard (UI Polish 1).
///
/// Fails when code OUTSIDE `lib/shared/theme/` uses
///   * `Color(0x…)` or `Color.fromRGBO(…)`,
///   * `Colors.<anything but transparent>`,
///   * a legacy `AppColors.<name>` constant (emerald, orange, info, ...).
/// Colours come from `context.colors` (the tokens) instead.
///
/// UI Polish 1 deliberately did not restyle screens, so the files that still
/// use the old palette are listed in `ui_guard_allowlist.txt` WITH A COUNT.
/// It is a ratchet:
///   * a file not in the list may not have any violation;
///   * a listed file may never go ABOVE its count;
///   * a listed file whose real count is LOWER must have its line updated
///     (so the list only ever shrinks). UI Polish 2 empties it.
///
/// Regenerate after migrating a screen:
///   UPDATE_UI_ALLOWLIST=1 flutter test test/ui_polish/ui_guard_test.dart
void main() {
  final violation = RegExp(
    r'(?<![A-Za-z_])Color\(0x'
    r'|(?<![A-Za-z_])Color\.fromRGBO'
    r'|(?<![A-Za-z_])Colors\.(?!transparent\b)[a-zA-Z]'
    r'|(?<![A-Za-z_])AppColors\.(emerald|orange|matteBlack|pureWhite|softGrey|'
    r'mediumGrey|borderGrey|darkCanvas|darkCard|darkSurface|darkHairline|'
    r'darkInkPrimary|darkInkSecondary|darkEmerald|splashGradientTop|'
    r'splashGradientMid|tierBronze|tierSilver|tierGold|tierPlatinum|'
    r'accentViolet|success|error|warning|info)\b',
  );

  Map<String, int> scan() {
    final counts = <String, int>{};
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final path = f.path.replaceAll('\\', '/');
      if (path.startsWith('lib/shared/theme/')) continue;
      var n = 0;
      for (final line in f.readAsLinesSync()) {
        final t = line.trimLeft();
        if (t.startsWith('//')) continue; // comments may name the old tokens
        n += violation.allMatches(line).length;
      }
      if (n > 0) counts[path] = n;
    }
    return counts;
  }

  Map<String, int> readAllowlist() {
    final file = File('test/ui_polish/ui_guard_allowlist.txt');
    if (!file.existsSync()) return {};
    final out = <String, int>{};
    for (final raw in file.readAsLinesSync()) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final parts = line.split(RegExp(r'\s+'));
      out[parts[0]] = int.parse(parts[1]);
    }
    return out;
  }

  test('no new hard-coded / legacy colours outside lib/shared/theme', () {
    final actual = scan();

    if (Platform.environment['UPDATE_UI_ALLOWLIST'] == '1') {
      final keys = actual.keys.toList()..sort();
      final b = StringBuffer()
        ..writeln('# Files that still use raw or legacy colours: "path count".')
        ..writeln(
            '# A ratchet: counts may only go DOWN. UI Polish 2 empties it.')
        ..writeln('# Regenerate: UPDATE_UI_ALLOWLIST=1 flutter test '
            'test/ui_polish/ui_guard_test.dart');
      for (final k in keys) {
        b.writeln('$k ${actual[k]}');
      }
      File('test/ui_polish/ui_guard_allowlist.txt')
          .writeAsStringSync(b.toString());
      return;
    }

    final allowed = readAllowlist();
    final problems = <String>[];
    actual.forEach((path, n) {
      final a = allowed[path];
      if (a == null) {
        problems.add('$path: $n colour violation(s), file is not allowlisted');
      } else if (n > a) {
        problems
            .add('$path: $n violations, allowlist says $a (may only go down)');
      } else if (n < a) {
        problems.add('$path: down to $n (allowlist says $a) — update the list');
      }
    });
    allowed.forEach((path, a) {
      if (!actual.containsKey(path)) {
        problems.add('$path: clean now — remove it from the allowlist');
      }
    });
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the theme folder itself is the only home of raw colours', () {
    // Shared widgets written for UI Polish 1 must be clean (not allowlisted).
    final allowed = readAllowlist();
    const mustBeClean = [
      'lib/shared/widgets/buttons/app_button.dart',
      'lib/shared/widgets/buttons/app_icon_button.dart',
      'lib/shared/widgets/buttons/primary_button.dart',
      'lib/shared/widgets/buttons/secondary_button.dart',
      'lib/shared/widgets/dialogs/app_dialog.dart',
      'lib/shared/widgets/cards/app_card.dart',
      'lib/shared/widgets/lists/app_list_group.dart',
      'lib/shared/widgets/tabs/app_segmented_tabs.dart',
      'lib/shared/widgets/status/app_status_label.dart',
      'lib/shared/widgets/sheets/app_sheet.dart',
      'lib/shared/widgets/notice/app_inline_notice.dart',
      'lib/shared/widgets/tier/tier_header.dart',
      'lib/shared/widgets/navigation/app_glass_nav_bar.dart',
      'lib/shared/widgets/accordions/app_accordion_card.dart',
    ];
    for (final p in mustBeClean) {
      expect(allowed.containsKey(p), isFalse,
          reason: '$p must not be allowlisted');
    }
  });

  test('the guard regex catches what it should', () {
    for (final bad in [
      'color: Color(0xFF123456)',
      'Color.fromRGBO(1, 2, 3, 1)',
      'color: Colors.red',
      'AppColors.orange',
      'AppColors.info.withValues(alpha: .1)',
    ]) {
      expect(violation.hasMatch(bad), isTrue, reason: bad);
    }
    for (final ok in [
      'Colors.transparent',
      'context.colors.brand',
      'AppColors.light',
      'AppColors.barrier',
      'MyColors.red',
    ]) {
      expect(violation.hasMatch(ok), isFalse, reason: ok);
    }
  });
}
