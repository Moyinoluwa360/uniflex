// Pack 2 / Part B — bug fixes that are checkable from source.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('B-02 the kitchen queue filters on the server, admin lists are bounded',
      () {
    final src = _read('lib/admin/services/admin_service.dart');
    final kitchen = src.substring(src.indexOf('fetchKitchenOrders() async'));
    final kitchenQuery = kitchen.substring(0, kitchen.indexOf('final now'));
    expect(kitchenQuery.contains(".eq('type', 'food')"), isTrue);
    expect(kitchenQuery.contains(".isFilter('delivery_group_id', null)"), isTrue);
    expect(kitchenQuery.contains(".eq('delivery_type', 'pickup')"), isTrue);
    expect(kitchenQuery.contains(".inFilter('status', _kitchenStatuses)"), isTrue);
    expect(kitchenQuery.contains('.limit('), isTrue);

    for (final marker in [
      'streamAllDeliveryGroups() async*',
      'streamErrandOrders() async*',
    ]) {
      final body = src.substring(src.indexOf(marker));
      final query = body.substring(0, body.indexOf('if (rows.isEmpty)'));
      expect(query.contains('.limit(500)'), isTrue, reason: marker);
    }
  });

  test('B-03 no raw error text on the profile screen or the PIN sheet', () {
    final profile = _read('lib/student/profile/student_profile_screen.dart');
    expect(profile.contains("Text('Error: \$e')"), isFalse);
    final pin = _read('lib/shared/widgets/pin/pin_entry_sheet.dart');
    expect(pin.contains('e.toString()'), isFalse);
  });

  test('B-03b no screen interpolates a raw exception into visible text', () {
    final raw = RegExp(r"""Text\('[^'\n]*\$e'|'[^'\n]*: \$e'|\(\$e\)'""");
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('debugPrint')) continue;
        if (raw.hasMatch(lines[i])) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty);
  });

  test('C-ios iPhone-only build (no iPad screenshots / layout review)', () {
    final pbx = _read('ios/Runner.xcodeproj/project.pbxproj');
    expect(pbx.contains('TARGETED_DEVICE_FAMILY = "1,2"'), isFalse);
    expect(RegExp('TARGETED_DEVICE_FAMILY = 1;').allMatches(pbx).length, 3);
  });

  test('C-play the budget is never called a "saving plan" on screen', () {
    for (final f in [
      'lib/student/wallet/saving_plan_screen.dart',
      'lib/student/wallet/wallet_screen.dart',
      'lib/student/ordering/commitment_fee_screen.dart',
    ]) {
      expect(RegExp(r"'[^'\n]*[Ss]aving [Pp]lan[^'\n]*'").hasMatch(_read(f)), isFalse,
          reason: f);
    }
  });
}
