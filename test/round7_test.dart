// Pure unit tests for Round 7 features — no widgets, no Supabase, instant.
//
// Covers:
//   • Pack capacity constant (8 spoons)
//   • Product.isMeal / isProteinTopping classification
//   • Delivery fee calculation (deliveryFeePerVendor helper)
//   • Multi-vendor cart grouping, aggregation, and serialization round-trip
//   • Legacy v1 → v2 cart migration

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/constants/pack_constants.dart';
import 'package:uniflex/shared/models/cart_item.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/student/ordering/cart_provider.dart';
import 'package:uniflex/student/ordering/order_repository.dart';

// ── Test helpers ─────────────────────────────────────────────────────────────

Vendor _vendor({
  String id = 'v1',
  String name = 'Uniflex Kitchen',
  bool isFeatured = true,
  String? badgeLabel = 'Major',
  double packPrice = 200,
}) =>
    Vendor(
      id: id,
      name: name,
      description: '',
      isFeatured: isFeatured,
      isActive: true,
      badgeLabel: badgeLabel,
      packPrice: packPrice,
    );

Product _product({
  String id = 'p1',
  String vendorId = 'v1',
  String name = 'Jollof Rice',
  double basePrice = 500,
  String section = 'food',
  String? foodSubsection = 'meal',
  bool requiresPack = true,
}) =>
    Product(
      id: id,
      vendorId: vendorId,
      name: name,
      description: '',
      category: 'meals',
      basePrice: basePrice,
      section: section,
      foodSubsection: foodSubsection,
      requiresPack: requiresPack,
    );

CartItem _item({
  String id = 'p1',
  String vendorId = 'v1',
  String name = 'Jollof Rice',
  double basePrice = 500,
  int quantity = 1,
  String section = 'food',
  String? foodSubsection = 'meal',
}) =>
    CartItem(
      product: _product(
        id: id,
        vendorId: vendorId,
        name: name,
        basePrice: basePrice,
        section: section,
        foodSubsection: foodSubsection,
      ),
      quantity: quantity,
    );

// ── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Pack capacity ──────────────────────────────────────────────────────

  group('Pack capacity constant', () {
    test('kPackMealCapacity is 8', () {
      expect(kPackMealCapacity, 8);
    });
  });

  // ── Product classification ─────────────────────────────────────────────

  group('Product.isMeal / isProteinTopping', () {
    test('meal items count toward pack capacity', () {
      final p = _product(section: 'food', foodSubsection: 'meal');
      expect(p.isMeal, isTrue);
      expect(p.isProteinTopping, isFalse);
    });

    test('protein toppings do not count toward capacity', () {
      final p = _product(section: 'food', foodSubsection: 'protein_topping');
      expect(p.isMeal, isFalse);
      expect(p.isProteinTopping, isTrue);
    });

    test('drinks are neither meal nor protein topping', () {
      final p = _product(section: 'drinks', foodSubsection: null);
      expect(p.isMeal, isFalse);
      expect(p.isProteinTopping, isFalse);
    });

    test('sectionLabel returns correct display text', () {
      expect(_product(section: 'food').sectionLabel, 'Food');
      expect(_product(section: 'drinks').sectionLabel, 'Drinks');
      expect(_product(section: 'others').sectionLabel, 'Others');
    });
  });

  // ── Delivery fee calculation ───────────────────────────────────────────

  group('deliveryFeePerVendor', () {
    test('returns campus fee from settings', () {
      final settings = {'campus_delivery_fee': '250'};
      expect(deliveryFeePerVendor(settings, 'campus_delivery'), 250.0);
    });

    test('returns hostel fee from settings', () {
      final settings = {'hostel_delivery_fee': '400'};
      expect(deliveryFeePerVendor(settings, 'hostel_delivery'), 400.0);
    });

    test('defaults to 200 when campus key missing', () {
      expect(deliveryFeePerVendor({}, 'campus_delivery'), 200.0);
    });

    test('defaults to 300 when hostel key missing', () {
      expect(deliveryFeePerVendor({}, 'hostel_delivery'), 300.0);
    });

    test('returns 0 for pickup', () {
      final settings = {
        'campus_delivery_fee': '250',
        'hostel_delivery_fee': '400',
      };
      expect(deliveryFeePerVendor(settings, 'pickup'), 0.0);
    });

    test('returns 0 for unknown delivery type', () {
      expect(deliveryFeePerVendor({}, 'drone_delivery'), 0.0);
    });
  });

  // ── Multi-vendor cart grouping ─────────────────────────────────────────

  group('CartState multi-vendor', () {
    late Vendor uniflex;
    late Vendor partner;

    setUp(() {
      uniflex = _vendor(id: 'v1', name: 'Uniflex', isFeatured: true, badgeLabel: 'Major');
      partner = _vendor(id: 'v2', name: 'Chicken Republic', isFeatured: false, badgeLabel: null);
    });

    test('empty cart has correct defaults', () {
      const cart = CartState();
      expect(cart.isEmpty, isTrue);
      expect(cart.vendorCount, 0);
      expect(cart.itemCount, 0);
      expect(cart.subtotal, 0.0);
      expect(cart.totalPackFee, 0.0);
      expect(cart.isUniflexOnly, isTrue);
      expect(cart.hasPartnerVendor, isFalse);
    });

    test('single uniflex vendor', () {
      final cart = CartState(groups: {
        'v1': VendorCartGroup(
          vendor: uniflex,
          items: [_item(id: 'p1', basePrice: 500, quantity: 2)],
          packCount: 1,
          packFee: 200,
        ),
      });

      expect(cart.isEmpty, isFalse);
      expect(cart.vendorCount, 1);
      expect(cart.itemCount, 2);
      expect(cart.subtotal, 1000.0);
      expect(cart.totalPackFee, 200.0);
      expect(cart.isUniflexOnly, isTrue);
      expect(cart.hasPartnerVendor, isFalse);
    });

    test('two vendors — mixed Uniflex and partner', () {
      final cart = CartState(groups: {
        'v1': VendorCartGroup(
          vendor: uniflex,
          items: [_item(id: 'p1', basePrice: 500, quantity: 1)],
          packCount: 1,
          packFee: 200,
        ),
        'v2': VendorCartGroup(
          vendor: partner,
          items: [
            _item(id: 'p2', vendorId: 'v2', basePrice: 800, quantity: 1),
            _item(id: 'p3', vendorId: 'v2', basePrice: 300, quantity: 3),
          ],
          packCount: 1,
          packFee: 200,
        ),
      });

      expect(cart.vendorCount, 2);
      expect(cart.itemCount, 5); // 1 + 1 + 3
      expect(cart.subtotal, 500 + 800 + 900);
      expect(cart.totalPackFee, 400.0); // 200 + 200
      expect(cart.isUniflexOnly, isFalse);
      expect(cart.hasPartnerVendor, isTrue);
    });

    test('vendor getter returns single vendor when only one group', () {
      final cart = CartState(groups: {
        'v1': VendorCartGroup(
          vendor: uniflex,
          items: [_item()],
        ),
      });
      expect(cart.vendor?.id, 'v1');
    });

    test('VendorCartGroup.totalWithPacks includes pack fee', () {
      final group = VendorCartGroup(
        vendor: uniflex,
        items: [_item(basePrice: 500, quantity: 2)],
        packCount: 2,
        packFee: 400,
      );
      expect(group.subtotal, 1000.0);
      expect(group.totalWithPacks, 1400.0);
    });
  });

  // ── Cart serialization round-trip ──────────────────────────────────────

  group('CartState JSON round-trip', () {
    test('serialize → deserialize produces equal state', () {
      final vendor = _vendor(id: 'v1');
      final original = CartState(groups: {
        'v1': VendorCartGroup(
          vendor: vendor,
          items: [
            _item(id: 'p1', basePrice: 500, quantity: 2),
            _item(
              id: 'p2',
              basePrice: 300,
              quantity: 1,
              section: 'drinks',
              foodSubsection: null,
            ),
          ],
          packCount: 1,
          packFee: 200,
          packContents: [
            {'p1': 2},
          ],
        ),
      });

      final json = jsonEncode(original.toJson());
      final restored = CartState.fromJson(jsonDecode(json) as Map<String, dynamic>);

      expect(restored.vendorCount, original.vendorCount);
      expect(restored.itemCount, original.itemCount);
      expect(restored.subtotal, original.subtotal);
      expect(restored.totalPackFee, original.totalPackFee);
      expect(restored.groups['v1']!.packContents.length, 1);
      expect(restored.groups['v1']!.packContents[0]['p1'], 2);
    });

    test('version 2 marker is set', () {
      const cart = CartState();
      final json = cart.toJson();
      expect(json['version'], 2);
    });
  });

  // ── Legacy v1 cart migration ───────────────────────────────────────────

  group('CartState legacy migration', () {
    test('v1 single-vendor format migrates to v2 groups', () {
      final v1Json = {
        'vendor': _vendor(id: 'v1').toMap(),
        'items': [
          _item(id: 'p1', basePrice: 500, quantity: 1).toJson(),
        ],
      };

      final cart = CartState.fromJson(v1Json);

      expect(cart.groups.length, 1);
      expect(cart.groups['v1'], isNotNull);
      expect(cart.groups['v1']!.items.length, 1);
      expect(cart.groups['v1']!.items.first.product.id, 'p1');
      expect(cart.groups['v1']!.packCount, 0);
    });

    test('v1 with no vendor returns empty cart', () {
      final v1Json = {
        'items': [_item().toJson()],
      };
      final cart = CartState.fromJson(v1Json);
      expect(cart.isEmpty, isTrue);
    });

    test('v1 with no items returns empty cart', () {
      final v1Json = {
        'vendor': _vendor().toMap(),
        'items': <dynamic>[],
      };
      final cart = CartState.fromJson(v1Json);
      expect(cart.isEmpty, isTrue);
    });

    test('malformed v1 JSON returns empty cart', () {
      final cart = CartState.fromJson({'garbage': true});
      expect(cart.isEmpty, isTrue);
    });
  });

  // ── MultiVendorOrderResult ─────────────────────────────────────────────

  group('MultiVendorOrderResult', () {
    test('stores delivery group info correctly', () {
      const result = MultiVendorOrderResult(
        groupId: 'g1',
        commitmentFeeTotal: 600,
        vendorCount: 3,
      );
      expect(result.groupId, 'g1');
      expect(result.commitmentFeeTotal, 600);
      expect(result.vendorCount, 3);
    });
  });
}
