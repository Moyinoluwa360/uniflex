// Pure unit tests for Fix Pack 2 — no widgets, no Supabase, instant.
//
// Covers:
//   • DeliveryGroupStatus enum: new riderAccepted value, labels, roundtrip
//   • DeliveryGroup model: cancelledByStudent, isTerminal, shortId
//   • GroupCustomerInfo: fromMap, displayName, PIN only when provided
//   • GroupLineItem: lineTotal, section helpers on GroupVendorItems
//   • GroupPack: label
//   • Final-price validation constants (> 0, ≤ 500,000 — mirrors SQL RPC)

import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/shared/models/delivery_group.dart';
import 'package:uniflex/rider/services/rider_service.dart';

void main() {
  // ── DeliveryGroupStatus ──────────────────────────────────────────────────

  group('DeliveryGroupStatus', () {
    test('fromString covers all 7 values', () {
      expect(DeliveryGroupStatus.fromString('placed'), DeliveryGroupStatus.placed);
      expect(DeliveryGroupStatus.fromString('commitment_paid'), DeliveryGroupStatus.commitmentPaid);
      expect(DeliveryGroupStatus.fromString('rider_accepted'), DeliveryGroupStatus.riderAccepted);
      expect(DeliveryGroupStatus.fromString('awaiting_final_payment'), DeliveryGroupStatus.awaitingFinalPayment);
      expect(DeliveryGroupStatus.fromString('out_for_delivery'), DeliveryGroupStatus.outForDelivery);
      expect(DeliveryGroupStatus.fromString('completed'), DeliveryGroupStatus.completed);
      expect(DeliveryGroupStatus.fromString('cancelled'), DeliveryGroupStatus.cancelled);
    });

    test('fromString unknown value → placed (safe default)', () {
      expect(DeliveryGroupStatus.fromString(''), DeliveryGroupStatus.placed);
      expect(DeliveryGroupStatus.fromString('legacy_status'), DeliveryGroupStatus.placed);
    });

    test('rawValue roundtrips back through fromString', () {
      for (final s in DeliveryGroupStatus.values) {
        expect(DeliveryGroupStatus.fromString(s.rawValue), s,
            reason: '${s.rawValue} should roundtrip');
      }
    });

    test('labels are non-empty for all values', () {
      for (final s in DeliveryGroupStatus.values) {
        expect(s.label.isNotEmpty, isTrue, reason: '$s has empty label');
      }
    });

    test('riderAccepted label is "Rider Accepted"', () {
      expect(DeliveryGroupStatus.riderAccepted.label, 'Rider Accepted');
    });

    test('commitmentPaid label is "In Rider Pool" (pool-facing wording)', () {
      expect(DeliveryGroupStatus.commitmentPaid.label, 'In Rider Pool');
    });

    test('only completed and cancelled are terminal', () {
      final nonTerminal = [
        DeliveryGroupStatus.placed,
        DeliveryGroupStatus.commitmentPaid,
        DeliveryGroupStatus.riderAccepted,
        DeliveryGroupStatus.awaitingFinalPayment,
        DeliveryGroupStatus.outForDelivery,
      ];
      for (final s in nonTerminal) {
        // Build a minimal group and check isTerminal.
        final g = _makeGroup(status: s);
        expect(g.isTerminal, isFalse, reason: '$s should not be terminal');
      }
      expect(_makeGroup(status: DeliveryGroupStatus.completed).isTerminal, isTrue);
      expect(_makeGroup(status: DeliveryGroupStatus.cancelled).isTerminal, isTrue);
    });
  });

  // ── DeliveryGroup model ──────────────────────────────────────────────────

  group('DeliveryGroup', () {
    test('shortId is # + first 8 chars uppercased', () {
      final g = _makeGroup(id: 'abcdef01-0000-0000-0000-000000000000');
      expect(g.shortId, '#ABCDEF01');
    });

    test('cancelledByStudent defaults to false', () {
      final g = _makeGroup();
      expect(g.cancelledByStudent, isFalse);
    });

    test('fromMap parses cancelledByStudent from JSON', () {
      final g = DeliveryGroup.fromMap(_baseMap()..['cancelled_by_student'] = true);
      expect(g.cancelledByStudent, isTrue);
    });

    test('fromMap missing cancelled_by_student → false', () {
      final map = _baseMap()..remove('cancelled_by_student');
      final g = DeliveryGroup.fromMap(map);
      expect(g.cancelledByStudent, isFalse);
    });

    test('fromMap parses riderAccepted status correctly', () {
      final map = _baseMap()..['status'] = 'rider_accepted';
      final g = DeliveryGroup.fromMap(map);
      expect(g.status, DeliveryGroupStatus.riderAccepted);
    });

    test('fromMap parses finalAmount as double', () {
      final map = _baseMap()..['final_amount'] = 2500;
      final g = DeliveryGroup.fromMap(map);
      expect(g.finalAmount, 2500.0);
    });

    test('fromMap null finalAmount → null', () {
      final map = _baseMap()..['final_amount'] = null;
      final g = DeliveryGroup.fromMap(map);
      expect(g.finalAmount, isNull);
    });
  });

  // ── GroupCustomerInfo ────────────────────────────────────────────────────

  group('GroupCustomerInfo', () {
    test('displayName without nickname shows fullName only', () {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Ada Okafor',
        'phone': '07000000000',
      });
      expect(info.displayName, 'Ada Okafor');
    });

    test('displayName with nickname appends @nickname', () {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Ada Okafor',
        'nickname': 'ada',
        'phone': '07000000000',
      });
      expect(info.displayName, 'Ada Okafor (@ada)');
    });

    test('deliveryPin is null before out_for_delivery (RPC redacts it)', () {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Test',
        'phone': '0700',
        'delivery_pin': null,
      });
      expect(info.deliveryPin, isNull);
    });

    test('deliveryPin is populated when RPC returns it', () {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Test',
        'phone': '0700',
        'delivery_pin': 'A3F9',
      });
      expect(info.deliveryPin, 'A3F9');
    });

    test('fromMap uses "Customer" fallback for missing full_name', () {
      final info = GroupCustomerInfo.fromMap({'phone': '0700'});
      expect(info.fullName, 'Customer');
    });

    test('fromMap uses empty string fallback for missing phone', () {
      final info = GroupCustomerInfo.fromMap({'full_name': 'X'});
      expect(info.phone, '');
    });
  });

  // ── GroupLineItem & GroupVendorItems helpers ─────────────────────────────

  group('GroupLineItem', () {
    test('lineTotal = unitPrice × quantity', () {
      final item = GroupLineItem.fromMap({
        'product_name': 'Jollof Rice',
        'quantity': 3,
        'unit_price': 1200,
        'section': 'food',
      });
      expect(item.lineTotal, 3600.0);
    });

    test('fromMap defaults section to "others" when missing', () {
      final item = GroupLineItem.fromMap({
        'product_name': 'Mystery',
        'quantity': 1,
        'unit_price': 500,
      });
      expect(item.section, 'others');
    });
  });

  group('GroupVendorItems section helpers', () {
    final vendor = GroupVendorItems(
      vendorId: 'v1',
      vendorName: 'Test Vendor',
      items: [
        GroupLineItem.fromMap({'product_name': 'Rice', 'quantity': 1, 'unit_price': 500, 'section': 'food'}),
        GroupLineItem.fromMap({'product_name': 'Coke', 'quantity': 2, 'unit_price': 300, 'section': 'drinks'}),
        GroupLineItem.fromMap({'product_name': 'Sachet', 'quantity': 1, 'unit_price': 50, 'section': 'others'}),
      ],
      packs: [],
      subtotal: 1150,
    );

    test('foodItems returns only food section', () {
      expect(vendor.foodItems.map((i) => i.productName), ['Rice']);
    });

    test('drinkItems returns only drinks section', () {
      expect(vendor.drinkItems.map((i) => i.productName), ['Coke']);
    });

    test('otherItems returns everything else', () {
      expect(vendor.otherItems.map((i) => i.productName), ['Sachet']);
    });
  });

  // ── GroupPack ────────────────────────────────────────────────────────────

  group('GroupPack', () {
    test('label is 1-indexed ("Pack 1" for packIndex 0)', () {
      expect(GroupPack(packIndex: 0, items: []).label, 'Pack 1');
      expect(GroupPack(packIndex: 2, items: []).label, 'Pack 3');
    });
  });

  // ── Final-price validation constants ─────────────────────────────────────
  //
  // These match the SQL RPC guards in fix_pack_2.sql:
  //   p_final_amount > 0 AND p_final_amount <= 500000
  //
  // The Dart UI should refuse to submit outside this range before hitting
  // the RPC. These tests document the accepted range, not UI code, so the
  // spec stays green even if the UI implementation is later refactored.

  group('Final-price acceptance range', () {
    bool isValidFinalPrice(double amount) =>
        amount > 0 && amount <= 500000;

    test('0 is rejected', () => expect(isValidFinalPrice(0), isFalse));
    test('negative is rejected', () => expect(isValidFinalPrice(-1), isFalse));
    test('1 is accepted (minimum positive)', () => expect(isValidFinalPrice(1), isTrue));
    test('500000 is accepted (upper bound)', () => expect(isValidFinalPrice(500000), isTrue));
    test('500001 is rejected (over cap)', () => expect(isValidFinalPrice(500001), isFalse));
    test('typical delivery price 2500 is accepted', () => expect(isValidFinalPrice(2500), isTrue));
  });
}

// ── Helpers ────────────────────────────────────────────────────────────────

Map<String, dynamic> _baseMap({String? id, String? status}) => {
      'id': id ?? '00000000-0000-0000-0000-000000000000',
      'student_id': 'student-1',
      'delivery_type': 'delivery',
      'commitment_fee_total': 300,
      'final_payment_paid': false,
      'status': status ?? 'placed',
      'created_at': '2026-01-01T00:00:00.000Z',
    };

DeliveryGroup _makeGroup({
  String? id,
  DeliveryGroupStatus status = DeliveryGroupStatus.placed,
}) {
  return DeliveryGroup.fromMap(_baseMap(
    id: id,
    status: status.rawValue,
  ));
}
