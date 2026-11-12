// Widget test: CatalogScreen always renders Food, Drinks, and Others sections.
//
// Verifies:
//   • All three section headers appear regardless of product mix.
//   • Empty sections show a placeholder message.
//   • Products with unknown section fall into Others.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/student/ordering/catalog_screen.dart';
import 'package:uniflex/student/ordering/product_repository.dart';

// ── Helpers ──────────────────────────────────────────────────────────────

Vendor _vendor() => const Vendor(
      id: 'v1',
      name: 'Test Vendor',
      description: '',
      isFeatured: true,
      isActive: true,
      badgeLabel: 'Major',
      packPrice: 200,
    );

Product _product({
  required String id,
  required String name,
  required String section,
  String? foodSubsection,
  String category = 'test',
  double basePrice = 500,
}) =>
    Product(
      id: id,
      vendorId: 'v1',
      name: name,
      description: '',
      category: category,
      basePrice: basePrice,
      section: section,
      foodSubsection: foodSubsection,
    );

Widget _buildApp({
  required Vendor vendor,
  required List<Product> products,
}) {
  return ProviderScope(
    overrides: [
      vendorProductsProvider(vendor.id)
          .overrideWith((ref) => Future.value(products)),
    ],
    child: MaterialApp(
      home: CatalogScreen(vendor: vendor),
    ),
  );
}

/// Opens one of the (closed by default) Drinks / Others dropdowns.
Future<void> _open(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

// ── Tests ────────────────────────────────────────────────────────────────

void main() {
  testWidgets('All 3 section headers render with products in each',
      (tester) async {
    final products = [
      _product(
        id: 'p1',
        name: 'Jollof Rice',
        section: 'food',
        foodSubsection: 'meal',
      ),
      _product(
        id: 'p2',
        name: 'Chicken',
        section: 'food',
        foodSubsection: 'protein_topping',
      ),
      _product(id: 'p3', name: 'Zobo', section: 'drinks'),
      _product(id: 'p4', name: 'Shawarma', section: 'others'),
    ];

    await tester.pumpWidget(_buildApp(vendor: _vendor(), products: products));
    await tester.pumpAndSettle();

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);

    // Food section shows the card link (not inline products).
    expect(find.text('Order Food (Packs)'), findsOneWidget);
    // Drinks and Others are dropdowns (closed at first); open each.
    await _open(tester, 'Drinks');
    expect(find.text('Zobo'), findsOneWidget);
    await _open(tester, 'Others');
    expect(find.text('Shawarma'), findsOneWidget);
  });

  testWidgets('Empty sections show placeholder message', (tester) async {
    // Only food products — Drinks and Others are empty.
    final products = [
      _product(
        id: 'p1',
        name: 'Jollof Rice',
        section: 'food',
        foodSubsection: 'meal',
      ),
    ];

    await tester.pumpWidget(_buildApp(vendor: _vendor(), products: products));
    await tester.pumpAndSettle();

    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);

    await _open(tester, 'Drinks');
    expect(find.text('No drinks available right now.'), findsOneWidget);
    await _open(tester, 'Others');
    expect(find.text('No other items available right now.'), findsOneWidget);
  });

  testWidgets('Unknown section products appear under Others', (tester) async {
    final products = [
      _product(id: 'p1', name: 'Mystery Item', section: 'unknown_section'),
    ];

    await tester.pumpWidget(_buildApp(vendor: _vendor(), products: products));
    await tester.pumpAndSettle();

    // All headers visible.
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Drinks'), findsOneWidget);
    expect(find.text('Others'), findsOneWidget);

    // Mystery Item renders under Others (not hidden).
    await _open(tester, 'Others');
    expect(find.text('Mystery Item'), findsOneWidget);
    // Food and Drinks are empty.
    expect(find.text('No food items available right now.'), findsOneWidget);
    await _open(tester, 'Drinks');
    expect(find.text('No drinks available right now.'), findsOneWidget);
  });
}
