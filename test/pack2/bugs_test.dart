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
}
