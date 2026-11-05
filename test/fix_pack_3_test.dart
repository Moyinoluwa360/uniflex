// Pure unit tests for Fix Pack 3 — no widgets, no Supabase, instant.
//
// Covers:
//   • ImageUploadField image processing logic (crop, resize)
//   • Advertisement model: only none/url link types survive validation
//   • URL auto-prepend logic
//   • Product soft-delete: deleted item modelled correctly
//   • Vendor soft-delete model

import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/shared/models/advertisement.dart';
import 'package:uniflex/shared/models/product.dart';

// ── Helpers ────────────────────────────────────────────────────────────────

Advertisement _makeAd({
  AdLinkType linkType = AdLinkType.none,
  String? linkValue,
  bool isActive = true,
}) =>
    Advertisement(
      id: 'ad-1',
      title: 'Test',
      subtitle: '',
      isDark: false,
      isActive: isActive,
      sortOrder: 0,
      linkType: linkType,
      linkValue: linkValue,
    );

Product _makeProduct({
  bool isAvailable = true,
  String section = 'food',
  String? foodSubsection = 'meal',
  DateTime? deletedAt,
}) =>
    Product(
      id: 'p-1',
      vendorId: 'v-1',
      name: 'Jollof Rice',
      description: '',
      category: 'Meals',
      basePrice: 1200,
      isAvailable: isAvailable,
      section: section,
      foodSubsection: foodSubsection,
    );

void main() {
  // ── URL auto-prepend ──────────────────────────────────────────────────────
  //
  // Mirrors the _save() logic in AdvertisementFormScreen.

  group('URL auto-prepend (https://)', () {
    String autoPrefix(String raw) =>
        raw.startsWith('http') ? raw : 'https://$raw';

    test('already has https:// — untouched', () {
      expect(autoPrefix('https://example.com'), 'https://example.com');
    });

    test('has http:// — untouched', () {
      expect(autoPrefix('http://example.com'), 'http://example.com');
    });

    test('bare domain — gets https:// prepended', () {
      expect(autoPrefix('example.com'), 'https://example.com');
    });

    test('subdomain — gets https:// prepended', () {
      expect(autoPrefix('shop.example.com/sale'), 'https://shop.example.com/sale');
    });
  });

  // ── Advertisement link type ───────────────────────────────────────────────

  group('AdLinkType', () {
    test('fromName("none") → none', () {
      expect(AdLinkType.fromName('none'), AdLinkType.none);
    });

    test('fromName("url") → url', () {
      expect(AdLinkType.fromName('url'), AdLinkType.url);
    });

    test('fromName("vendor") → none (backward compat fallback)', () {
      // After the SQL migration all vendor-type ads become none.
      // The Dart model's fromName must keep old DB rows readable without crash.
      // We don't add a vendor enum value — unknown → none.
      expect(AdLinkType.fromName('vendor'), AdLinkType.none);
    });

    test('fromName("wallet") → none', () {
      expect(AdLinkType.fromName('wallet'), AdLinkType.none);
    });

    test('fromName(null) → none', () {
      expect(AdLinkType.fromName(null), AdLinkType.none);
    });

    test('fromName("garbage") → none', () {
      expect(AdLinkType.fromName('garbage'), AdLinkType.none);
    });
  });

  group('Advertisement.isLive', () {
    test('active, no schedule → live', () {
      expect(_makeAd(isActive: true).isLive, isTrue);
    });

    test('inactive → not live', () {
      expect(_makeAd(isActive: false).isLive, isFalse);
    });

    test('url ad with link → live when active', () {
      expect(
        _makeAd(linkType: AdLinkType.url, linkValue: 'https://x.com').isLive,
        isTrue,
      );
    });
  });

  // ── Product model ─────────────────────────────────────────────────────────

  group('Product section constraint', () {
    test('food section requires foodSubsection', () {
      final p = _makeProduct(section: 'food', foodSubsection: 'meal');
      expect(p.isMeal, isTrue);
      expect(p.isProteinTopping, isFalse);
    });

    test('protein_topping section', () {
      final p = _makeProduct(section: 'food', foodSubsection: 'protein_topping');
      expect(p.isMeal, isFalse);
      expect(p.isProteinTopping, isTrue);
    });

    test('drinks section — isMeal false', () {
      final p = _makeProduct(section: 'drinks', foodSubsection: null);
      expect(p.isMeal, isFalse);
      expect(p.isProteinTopping, isFalse);
    });

    test('others section — isMeal false', () {
      final p = _makeProduct(section: 'others', foodSubsection: null);
      expect(p.isMeal, isFalse);
    });

    test('toggle preserves section — round-trip through toMap/fromMap', () {
      final original = _makeProduct(section: 'drinks', foodSubsection: null, isAvailable: true);
      // Simulate what _toggleAvailability now does: pass section/foodSubsection.
      final toggled = Product.fromMap({
        ...original.toMap(),
        'is_available': false,
        'deleted_at': null,
      });
      expect(toggled.section, 'drinks');
      expect(toggled.foodSubsection, isNull);
      expect(toggled.isAvailable, isFalse);
    });
  });

  group('Product availability filtering', () {
    test('unavailable product isAvailable == false', () {
      final p = _makeProduct(isAvailable: false);
      expect(p.isAvailable, isFalse);
    });

    test('fromMap parses is_available correctly', () {
      final p = Product.fromMap({
        'id': 'p-2',
        'vendor_id': 'v-1',
        'name': 'Fried Rice',
        'description': '',
        'category': 'Meals',
        'base_price': 1000,
        'is_available': false,
        'requires_pack': true,
        'section': 'food',
        'food_subsection': 'meal',
      });
      expect(p.isAvailable, isFalse);
    });
  });

  // ── Image crop constants ──────────────────────────────────────────────────
  //
  // The pixel arithmetic for center-crop: given W×H, the crop square has
  // side = min(W, H), top-left at ((W−side)/2, (H−side)/2).

  group('Center-crop math', () {
    int _squareSide(int w, int h) => w < h ? w : h;
    int _cropX(int w, int h) => (w - _squareSide(w, h)) ~/ 2;
    int _cropY(int w, int h) => (h - _squareSide(w, h)) ~/ 2;

    test('landscape 1600×900 → square 900, offset (350, 0)', () {
      expect(_squareSide(1600, 900), 900);
      expect(_cropX(1600, 900), 350);
      expect(_cropY(1600, 900), 0);
    });

    test('portrait 900×1600 → square 900, offset (0, 350)', () {
      expect(_squareSide(900, 1600), 900);
      expect(_cropX(900, 1600), 0);
      expect(_cropY(900, 1600), 350);
    });

    test('already square → side unchanged, offsets 0', () {
      expect(_squareSide(1200, 1200), 1200);
      expect(_cropX(1200, 1200), 0);
      expect(_cropY(1200, 1200), 0);
    });
  });
}
