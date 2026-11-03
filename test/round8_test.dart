// Pure unit tests for Round 8 features — no widgets, no Supabase, instant.
//
// Covers:
//   • Pack bracket fee calculation (packBrackets + vendorDeliveryFee)
//   • DeliveryLocation model
//   • Worked example: 3-vendor checkout with mixed pack counts

import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/models/delivery_location.dart';
import 'package:uniflex/student/ordering/order_repository.dart';

void main() {
  // ── Pack bracket calculation ───────────────────────────────────────

  group('packBrackets', () {
    test('0 packs → 1 bracket (minimum delivery charge)', () {
      expect(packBrackets(0), 1);
    });

    test('1 pack → 1 bracket', () {
      expect(packBrackets(1), 1);
    });

    test('2 packs → 1 bracket', () {
      expect(packBrackets(2), 1);
    });

    test('3 packs → 1 bracket', () {
      expect(packBrackets(3), 1);
    });

    test('4 packs → 2 brackets', () {
      expect(packBrackets(4), 2);
    });

    test('6 packs → 2 brackets', () {
      expect(packBrackets(6), 2);
    });

    test('7 packs → 3 brackets', () {
      expect(packBrackets(7), 3);
    });

    test('9 packs → 3 brackets', () {
      expect(packBrackets(9), 3);
    });

    test('10 packs → 4 brackets', () {
      expect(packBrackets(10), 4);
    });
  });

  // ── vendorDeliveryFee ─────────────────────────────────────────────

  group('vendorDeliveryFee', () {
    test('300 base × 1 bracket for 2 packs = 300', () {
      expect(vendorDeliveryFee(300, 2), 300.0);
    });

    test('300 base × 2 brackets for 4 packs = 600', () {
      expect(vendorDeliveryFee(300, 4), 600.0);
    });

    test('200 base × 1 bracket for 0 packs (drinks only) = 200', () {
      expect(vendorDeliveryFee(200, 0), 200.0);
    });

    test('300 base × 3 brackets for 7 packs = 900', () {
      expect(vendorDeliveryFee(300, 7), 900.0);
    });
  });

  // ── Worked example from spec ──────────────────────────────────────

  group('Worked example: Eng Hostel ₦300, 3 vendors', () {
    const locationPrice = 300.0;

    test('Uniflex 4 packs + QB 2 packs + CS drinks = ₦1200', () {
      final uniflexFee = vendorDeliveryFee(locationPrice, 4); // 2 brackets
      final qbFee = vendorDeliveryFee(locationPrice, 2); // 1 bracket
      final csFee = vendorDeliveryFee(locationPrice, 0); // 1 bracket (drinks)

      expect(uniflexFee, 600.0);
      expect(qbFee, 300.0);
      expect(csFee, 300.0);
      expect(uniflexFee + qbFee + csFee, 1200.0);
    });
  });

  // ── DeliveryLocation model ────────────────────────────────────────

  group('DeliveryLocation.fromMap', () {
    test('parses valid map', () {
      final loc = DeliveryLocation.fromMap({
        'id': 'loc-1',
        'name': 'Engineering Hostel',
        'price': 300,
        'is_active': true,
        'sort_order': 1,
      });

      expect(loc.id, 'loc-1');
      expect(loc.name, 'Engineering Hostel');
      expect(loc.price, 300.0);
      expect(loc.isActive, isTrue);
      expect(loc.sortOrder, 1);
    });

    test('handles numeric price as double', () {
      final loc = DeliveryLocation.fromMap({
        'id': 'loc-2',
        'name': 'Main Campus',
        'price': 250.50,
        'is_active': false,
        'sort_order': 0,
      });

      expect(loc.price, 250.50);
      expect(loc.isActive, isFalse);
    });
  });
}
