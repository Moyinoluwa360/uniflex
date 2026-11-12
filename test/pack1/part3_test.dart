// Pack 1 / Part 3 — fixed-menu vendor ordering style (widget + unit tests).
// The money rules are proven server-side in
// supabase/pack1_vendor_ordering_style_test.sql (39 checks, rolled back).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uniflex/admin/menu/product_form_screen.dart';
import 'package:uniflex/admin/menu/vendor_menu_manager.dart';
import 'package:uniflex/admin/services/admin_providers.dart';
import 'package:uniflex/admin/services/admin_service.dart';
import 'dart:typed_data';
import 'package:uniflex/admin/vendors/vendor_form_screen.dart';
import 'package:uniflex/shared/models/cart_item.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_models.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_widget.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/widgets/cart/cart_widgets.dart';
import 'package:uniflex/student/ordering/cart_provider.dart';
import 'package:uniflex/student/ordering/cart_screen.dart';
import 'package:uniflex/student/ordering/catalog_screen.dart';
import 'package:uniflex/student/ordering/checkout_draft.dart';
import 'package:uniflex/student/ordering/order_payment_repository.dart';
import 'package:uniflex/student/ordering/product_repository.dart';

// ── Test-only fixture: a fake cafeteria (never in any database) ────────
const _cafeteria = Vendor(
  id: 'caf',
  name: 'Test Cafeteria',
  description: '',
  isFeatured: false,
  isActive: true,
  badgeLabel: 'Partner',
  orderingStyle: VendorOrderingStyle.fixedMenu,
);

const _packVendor = Vendor(
  id: 'pv',
  name: 'Pack Vendor',
  description: '',
  isFeatured: false,
  isActive: true,
  badgeLabel: 'Partner',
);

Product _p(String id, String name, String category, double price,
        {String vendorId = 'caf',
        String section = 'food',
        String? sub = 'meal',
        String description = ''}) =>
    Product(
      id: id,
      vendorId: vendorId,
      name: name,
      description: description,
      category: category,
      basePrice: price,
      section: section,
      foodSubsection: sub,
    );

final _menu = [
  _p('d1', 'Coke 50cl', 'Drinks', 500),
  _p('r1', 'Rice with chicken and a very long name that has to wrap onto lines',
      'Rice', 3500,
      description: 'Jollof or fried'),
  _p('r2', 'Fried rice', 'Rice', 3000),
  _p('s1', 'Amala and ewedu', 'Swallow', 2500),
];

class _FakeAdmin implements AdminService {
  final vendorSaves = <Map<String, Object?>>[];
  final productSaves = <Map<String, Object?>>[];

  @override
  Future<String> uploadVendorImage(Uint8List bytes, String fileName) async =>
      'x';
  @override
  Future<String> uploadProductImage(Uint8List bytes, String fileName) async =>
      'x';

  @override
  Future<void> upsertVendor({
    String? id,
    required String name,
    required String description,
    required bool isActive,
    String? badgeLabel,
    String? imageUrl,
    String? location,
    String? contact,
    double? packPrice,
    String? orderingStyle,
  }) async =>
      vendorSaves
          .add({'id': id, 'name': name, 'ordering_style': orderingStyle});

  @override
  Future<void> upsertProduct({
    String? id,
    required String vendorId,
    required String name,
    required String description,
    required String category,
    required double basePrice,
    String? imageUrl,
    bool isAvailable = true,
    bool requiresPack = false,
    String section = 'food',
    String? foodSubsection,
  }) async =>
      productSaves.add({
        'name': name,
        'category': category,
        'price': basePrice,
        'requiresPack': requiresPack,
        'section': section,
        'sub': foodSubsection,
      });

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _TestCart extends CartNotifier {
  _TestCart(this._initial);
  final CartState _initial;
  @override
  CartState build() => _initial;
}

Widget _app(Widget home,
    {bool dark = false,
    double scale = 1.0,
    List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, w) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: home,
    ),
  );
}

void _variants(String name,
    Future<void> Function(WidgetTester t, bool dark, double scale) body) {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('$name (${dark ? 'dark' : 'light'}, x$scale)', (t) async {
        t.view.physicalSize = const Size(390, 844) * 2;
        t.view.devicePixelRatio = 2;
        addTearDown(t.view.reset);
        await body(t, dark, scale);
      });
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ── Model ─────────────────────────────────────────────────────────────
  group('model', () {
    test('missing / unknown style = pack-based (old rows, old saved carts)',
        () {
      final m = _packVendor.toMap()..remove('ordering_style');
      expect(Vendor.fromMap(m).orderingStyle, VendorOrderingStyle.packBased);
      expect(
          VendorOrderingStyle.parse('buffet'), VendorOrderingStyle.packBased);
      expect(Vendor.fromMap(_cafeteria.toMap()).isFixedMenu, isTrue);
      expect(kFixedMenuMaxQty, 20);
      expect(VendorOrderingStyle.packBased.label, 'Pack-based');
      expect(VendorOrderingStyle.fixedMenu.label, 'Fixed menu');
    });

    test('the cart snapshot keeps the style through save/restore', () {
      final cart = CartState(groups: {
        'caf': VendorCartGroup(vendor: _cafeteria, items: [
          CartItem(product: _menu[1], quantity: 2),
        ]),
      });
      final back = CartState.fromJson(cart.toJson());
      expect(back.groups['caf']!.vendor.isFixedMenu, isTrue);
    });

    test('checkout leg sends the style, product ids and quantities only', () {
      final cart = CartState(groups: {
        'caf': VendorCartGroup(vendor: _cafeteria, items: [
          CartItem(product: _menu[1], quantity: 2),
          CartItem(product: _menu[0], quantity: 1),
        ]),
        'pv': VendorCartGroup(
          vendor: _packVendor,
          items: [
            CartItem(
                product: _p('j', 'Jollof', 'Meals', 300, vendorId: 'pv'),
                quantity: 4),
          ],
          packCount: 1,
          packFee: 200,
          packContents: const [
            {'j': 4}
          ],
        ),
      });
      final draft = CheckoutDraft.fromCart(cart, isPickup: false);
      final caf = SupabaseOrderPaymentRepository.legForTest(
          draft.vendors.firstWhere((v) => v.vendorId == 'caf'));
      expect(caf['ordering_style'], 'fixed_menu');
      expect(caf['packs'], isEmpty);
      expect(caf['items'], [
        {'product_id': 'r1', 'quantity': 2},
        {'product_id': 'd1', 'quantity': 1},
      ]);
      final pv = SupabaseOrderPaymentRepository.legForTest(
          draft.vendors.firstWhere((v) => v.vendorId == 'pv'));
      expect(pv['ordering_style'], 'pack_based');
      expect((pv['packs'] as List).length, 1);
      // Display: no pack fee for the cafeteria; mixed cart still says packs.
      expect(draft.vendors.firstWhere((v) => v.vendorId == 'caf').packFee, 0);
    });

    test('friendly messages for the new server codes', () {
      expect(AppErrorMapper.map(Exception('VENDOR_STYLE_CHANGED')),
          contains('add them again'));
      expect(
          AppErrorMapper.map(Exception('QUANTITY_TOO_HIGH')), contains('20'));
      expect(AppErrorMapper.map(Exception('VENDOR_HAS_ACTIVE_ORDERS')),
          contains('orders in progress'));
    });

    test('categories group A→Z (admin and student use the same rule)', () {
      expect(
          groupByCategory(_menu).keys.toList(), ['Drinks', 'Rice', 'Swallow']);
    });
  });

  // ── Student vendor page ───────────────────────────────────────────────
  group('fixed-menu vendor page', () {
    _variants('dropdowns, add → stepper → max 20 → remove; no pack card',
        (t, dark, scale) async {
      await t.pumpWidget(_app(
        const CatalogScreen(vendor: _cafeteria),
        dark: dark,
        scale: scale,
        overrides: [
          vendorProductsProvider('caf').overrideWith((ref) async => _menu),
        ],
      ));
      await t.pumpAndSettle();

      expect(find.text('Order Food (Packs)'), findsNothing);
      expect(find.textContaining('pack', findRichText: true), findsNothing);
      for (final c in ['Drinks', 'Rice', 'Swallow']) {
        expect(find.text(c), findsOneWidget);
      }

      await t.tap(find.text('Rice'));
      await t.pumpAndSettle();
      final longName = find.textContaining('very long name');
      expect(longName, findsOneWidget);
      final nameText = t.widget<Text>(longName);
      expect(nameText.maxLines, isNull, reason: 'names wrap, no ellipsis');
      expect(nameText.style!.fontSize, greaterThanOrEqualTo(16));
      expect(find.text('Jollof or fried'), findsOneWidget);
      expect(find.text('₦3,500'), findsOneWidget);

      // Add → stepper at 1.
      await t.tap(find.byType(AddItemButton).first);
      await t.pumpAndSettle();
      expect(find.byType(QuantityStepper), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      // Up to the max; + then disabled.
      for (var i = 1; i < kFixedMenuMaxQty; i++) {
        await t.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(find.text('$kFixedMenuMaxQty'), findsOneWidget);
      final stepper = t.widget<QuantityStepper>(find.byType(QuantityStepper));
      expect(stepper.onPlus, isNull, reason: '+ disabled at the max');

      // Down to 0 removes the line.
      for (var i = 0; i < kFixedMenuMaxQty; i++) {
        final s = t.widget<QuantityStepper>(find.byType(QuantityStepper));
        s.onMinus!();
        await t.pump();
        if (find.byType(QuantityStepper).evaluate().isEmpty) break;
      }
      await t.pumpAndSettle();
      expect(find.byType(QuantityStepper), findsNothing);
      expect(find.byType(AddItemButton), findsNWidgets(2));
    });

    testWidgets('pack-based vendor page is unchanged', (t) async {
      await t.pumpWidget(_app(
        const CatalogScreen(vendor: _packVendor),
        overrides: [
          vendorProductsProvider('pv').overrideWith((ref) async => [
                _p('j', 'Jollof', 'Meals', 300, vendorId: 'pv'),
                _p('f', 'Fanta', 'Drinks', 400,
                    vendorId: 'pv', section: 'drinks', sub: null),
              ]),
        ],
      ));
      await t.pumpAndSettle();
      expect(find.text('Order Food (Packs)'), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
      expect(find.text('Others'), findsOneWidget);
      expect(find.text('Rice'), findsNothing);
    });
  });

  // ── Cart rows ────────────────────────────────────────────────────────
  group('cart', () {
    _variants('fixed-menu lines: plain rows with a stepper, no pack wording',
        (t, dark, scale) async {
      final cart = CartState(groups: {
        'caf': VendorCartGroup(vendor: _cafeteria, items: [
          CartItem(product: _menu[3], quantity: kFixedMenuMaxQty),
          CartItem(product: _menu[0], quantity: 2),
        ]),
      });
      await t.pumpWidget(_app(const CartScreen(),
          dark: dark,
          scale: scale,
          overrides: [cartProvider.overrideWith(() => _TestCart(cart))]));
      await t.pumpAndSettle();
      expect(find.text('Amala and ewedu'), findsOneWidget);
      expect(find.textContaining('pack', findRichText: true), findsNothing);
      final steppers =
          t.widgetList<QuantityStepper>(find.byType(QuantityStepper)).toList();
      expect(steppers.length, 2);
      expect(steppers[0].onPlus, isNull, reason: 'at the max');
      expect(steppers[1].onPlus, isNotNull);
    });
  });

  // ── Order item lists (student, rider and admin all use this view) ────
  group('order items', () {
    OrderBreakdownData data(Map<String, dynamic> vendor) =>
        OrderBreakdownData.fromJson({
          'order_id': 'g',
          'kind': 'delivery',
          'vendors': [vendor],
        });

    _variants('fixed-menu order: "2× Item", no pack headings',
        (t, dark, scale) async {
      await t.pumpWidget(_app(
        Scaffold(
          body: SingleChildScrollView(
            child: OrderBreakdownView(
              data: data({
                'vendor_id': 'caf',
                'vendor_name': 'Test Cafeteria',
                'packs': [],
                'items': [
                  {
                    'name': 'Rice with chicken',
                    'quantity': 2,
                    'unit_price': 3500,
                    'line_total': 7000
                  },
                  {
                    'name': 'Coke 50cl',
                    'quantity': 1,
                    'unit_price': 500,
                    'line_total': 500
                  },
                ],
                'drinks': [],
                'others': [],
                'item_count': 2,
                'vendor_total': 7500,
              }),
            ),
          ),
        ),
        dark: dark,
        scale: scale,
      ));
      await t.pumpAndSettle();
      expect(find.textContaining('2×', findRichText: true), findsOneWidget);
      expect(find.textContaining('Rice with chicken', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Pack', findRichText: true), findsNothing);
    });

    testWidgets('pack-based order still shows its packs', (t) async {
      await t.pumpWidget(_app(Scaffold(
        body: OrderBreakdownView(
          data: data({
            'vendor_id': 'pv',
            'vendor_name': 'Pack Vendor',
            'packs': [
              {
                'index': 1,
                'price': 200,
                'items': [
                  {'name': 'Jollof', 'quantity': 4}
                ]
              }
            ],
            'items': [],
            'drinks': [],
            'others': [],
            'item_count': 1,
            'vendor_total': 1400,
          }),
        ),
      )));
      await t.pumpAndSettle();
      expect(find.text('Pack 1 · ₦200'), findsOneWidget);
    });
  });

  // ── Admin ────────────────────────────────────────────────────────────
  group('admin', () {
    _variants('vendor form: ordering style control with one helper line',
        (t, dark, scale) async {
      final admin = _FakeAdmin();
      await t.pumpWidget(_app(const VendorFormScreen(),
          dark: dark,
          scale: scale,
          overrides: [adminServiceProvider.overrideWithValue(admin)]));
      await t.pumpAndSettle();
      expect(find.text('Ordering style'), findsOneWidget);
      expect(find.text('Pack-based'), findsOneWidget);
      expect(find.text('Fixed menu'), findsOneWidget);
      expect(find.text(VendorOrderingStyle.packBased.helper), findsOneWidget);
      expect(find.textContaining('Pack price'), findsOneWidget);

      await t.tap(find.text('Fixed menu'));
      await t.pumpAndSettle();
      expect(find.text(VendorOrderingStyle.fixedMenu.helper), findsOneWidget);
      expect(find.text(VendorOrderingStyle.packBased.helper), findsNothing);
      expect(find.textContaining('Pack price'), findsNothing,
          reason: 'pack-only field hidden for fixed menu');

      // Saving a new vendor sends the chosen style.
      await t.enterText(find.byType(TextFormField).first, 'Test Cafe');
      await t.ensureVisible(find.text('Add Vendor'));
      await t.tap(find.text('Add Vendor'));
      await t.pumpAndSettle();
      expect(admin.vendorSaves.single['ordering_style'], 'fixed_menu');
    });

    testWidgets('editing without changing the style does not resend it',
        (t) async {
      final admin = _FakeAdmin();
      await t.pumpWidget(_app(const VendorFormScreen(vendor: _cafeteria),
          overrides: [adminServiceProvider.overrideWithValue(admin)]));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Save Changes'));
      await t.tap(find.text('Save Changes'));
      await t.pumpAndSettle();
      expect(admin.vendorSaves.single['ordering_style'], isNull);
    });

    testWidgets('fixed-menu menu manager groups by category, one Add',
        (t) async {
      await t.pumpWidget(_app(Scaffold(
        body: FixedMenuBody(
          products: _menu,
          onAdd: () {},
          onEdit: (_) {},
          onDelete: (_) {},
          onToggle: (_, __) {},
        ),
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('add-fixed-item')), findsOneWidget);
      expect(find.text('Rice (2)'), findsOneWidget);
      expect(find.text('Drinks (1)'), findsOneWidget);
      expect(find.textContaining('Proteins'), findsNothing);
    });

    testWidgets('fixed-menu item form: category, no section / pack fields',
        (t) async {
      t.view.physicalSize = const Size(390, 1400) * 2;
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      final admin = _FakeAdmin();
      await t.pumpWidget(_app(
          const ProductFormScreen(
            vendorId: 'caf',
            fixedMenu: true,
            categorySuggestions: ['Drinks', 'Rice'],
          ),
          overrides: [adminServiceProvider.overrideWithValue(admin)]));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('form-category')), findsOneWidget);
      expect(find.byKey(const ValueKey('form-section-label')), findsNothing);
      expect(find.text('Rice'), findsOneWidget); // suggestion chip
      expect(find.textContaining('Price per portion'), findsOneWidget);

      Finder field(String key) => find.descendant(
          of: find.byKey(ValueKey(key)), matching: find.byType(EditableText));
      await t.enterText(field('form-name'), 'Ofada rice');
      await t.tap(find.text('Rice')); // category chip
      await t.pump();
      await t.enterText(field('form-price'), '4000');
      await t.ensureVisible(find.text('Add Item'));
      await t.tap(find.text('Add Item'));
      await t.pumpAndSettle();
      expect(admin.productSaves.single, {
        'name': 'Ofada rice',
        'category': 'Rice',
        'price': 4000.0,
        'requiresPack': false,
        'section': 'food',
        'sub': 'meal',
      });
    });
  });
}
