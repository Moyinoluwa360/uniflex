// Pack 4C tests — shared menu manager, support (inbox names, choice screen,
// WhatsApp), rider line, dashboard/analytics views and live refresh, ad popup
// and carousel, referral display. No Supabase and no emulator: pure widgets,
// fakes and provider overrides.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/admin/analytics/admin_analytics_screen.dart';
import 'package:uniflex/admin/dashboard/admin_dashboard_screen.dart';
import 'package:uniflex/admin/dashboard/money_cards.dart';
import 'package:uniflex/admin/menu/menu_management_screen.dart';
import 'package:uniflex/admin/menu/menu_section.dart';
import 'package:uniflex/admin/menu/vendor_menu_manager.dart';
import 'package:uniflex/admin/orders/admin_orders_screen.dart'
    show riderLineText;
import 'package:uniflex/admin/services/admin_providers.dart';
import 'package:uniflex/admin/services/admin_service.dart';
import 'package:uniflex/admin/services/profile_basics.dart';
import 'package:uniflex/admin/services/stats_live.dart';
import 'package:uniflex/admin/support/admin_support_inbox_screen.dart';
import 'package:uniflex/admin/support/support_settings_screen.dart';
import 'package:uniflex/admin/vendors/vendor_products_screen.dart';
import 'package:uniflex/shared/models/advertisement.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/support_conversation.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/shared/models/profile.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/auth/user_role.dart';
import 'package:uniflex/shared/services/settings/support_whatsapp_provider.dart';
import 'package:uniflex/shared/services/support/support_chat_service.dart';
import 'package:uniflex/shared/utils/ad_link.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/utils/phone_format.dart';
import 'package:uniflex/shared/widgets/navigation/app_bottom_nav_shell.dart';
import 'package:uniflex/shared/widgets/navigation/refresh_on_tab_visible.dart';
import 'package:uniflex/student/home/ad_carousel.dart';
import 'package:uniflex/student/home/ad_popup.dart';
import 'package:uniflex/student/profile/refer_a_student_screen.dart';
import 'package:uniflex/student/support/support_options_screen.dart';

// ── Fakes & fixtures ─────────────────────────────────────────────────────

class _FakeAdmin implements AdminService {
  final List<Map<String, Object?>> upserts = [];
  final List<(String, bool)> availability = [];
  final List<String> deleted = [];

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
  }) async {
    upserts.add({
      'id': id,
      'vendorId': vendorId,
      'name': name,
      'category': category,
      'basePrice': basePrice,
      'requiresPack': requiresPack,
      'section': section,
      'foodSubsection': foodSubsection,
    });
  }

  @override
  Future<void> setProductAvailability(String id, bool isAvailable) async {
    availability.add((id, isAvailable));
  }

  @override
  Future<void> deleteProduct(String id) async => deleted.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

Product _product(String id, String name,
        {String section = 'food',
        String? sub = 'meal',
        bool available = true}) =>
    Product(
      id: id,
      vendorId: 'v1',
      name: name,
      description: '',
      category: 'Food', // the legacy column that used to mis-file items
      basePrice: 500,
      isAvailable: available,
      requiresPack: section == 'food',
      section: section,
      foodSubsection: sub,
    );

const _uniflexVendor = Vendor(
  id: MenuManagementScreen.uniflexVendorId,
  name: 'Uniflex',
  description: '',
  isFeatured: true,
  isActive: true,
);
const _partnerVendor = Vendor(
  id: 'partner-1',
  name: 'Mama Put',
  description: '',
  isFeatured: false,
  isActive: true,
);

final _menu = [
  _product('m1', 'Jollof Rice'),
  _product('p1', 'Fried Chicken', sub: 'protein_topping'),
  _product('d1', 'Zobo', section: 'drinks', sub: null),
  _product('o1', 'Napkins', section: 'others', sub: null),
  _product('m2', 'White Rice', available: false),
];

/// A tall test screen so lazy ListViews build every row.
void _tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Widget _app(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      key: UniqueKey(), // a fresh scope each pump → no state carried over
      overrides: overrides,
      child: MaterialApp(home: child),
    );

List<Override> _menuOverrides(_FakeAdmin admin, List<Product> products) => [
      adminServiceProvider.overrideWithValue(admin),
      adminVendorProductsProvider
          .overrideWith((ref, vendorId) async => products),
      allVendorsProvider
          .overrideWith((ref) async => [_uniflexVendor, _partnerVendor]),
    ];

Advertisement _ad(String id,
        {String? image, AdLinkType type = AdLinkType.none, String? link}) =>
    Advertisement(
      id: id,
      title: 'Ad $id',
      subtitle: 'Sub $id',
      isDark: false,
      isActive: true,
      sortOrder: 0,
      imageUrl: image,
      linkType: type,
      linkValue: link,
    );

Profile _profile({String? nickname = 'Ada', String? fullName = 'Ada Obi'}) =>
    Profile(
      id: 'u1',
      role: UserRole.student,
      onboardingComplete: true,
      nickname: nickname,
      fullName: fullName,
      referralCode: 'ADA-REF-123',
      referralCount: 4,
    );

void main() {
  // ── 1. Menu ────────────────────────────────────────────────────────────
  group('Shared menu manager', () {
    test(
        'MenuSection.of follows the same section/subsection the student page uses',
        () {
      expect(MenuSection.of(_product('a', 'x')), MenuSection.meals);
      expect(MenuSection.of(_product('a', 'x', sub: 'protein_topping')),
          MenuSection.proteins);
      expect(MenuSection.of(_product('a', 'x', section: 'drinks', sub: null)),
          MenuSection.drinks);
      expect(MenuSection.of(_product('a', 'x', section: 'others', sub: null)),
          MenuSection.others);
      // Legacy 'Food' in the old category column no longer matters.
      expect(MenuSection.of(_product('a', 'x')).requiresPack, isTrue);
      expect(MenuSection.drinks.requiresPack, isFalse);
    });

    testWidgets('Uniflex AND a partner vendor render the same manager',
        (tester) async {
      final admin = _FakeAdmin();
      await tester.pumpWidget(_app(const MenuManagementScreen(),
          overrides: _menuOverrides(admin, _menu)));
      await tester.pumpAndSettle();
      expect(find.byType(VendorMenuManager), findsOneWidget);
      expect(
          tester
              .widget<VendorMenuManager>(find.byType(VendorMenuManager))
              .vendorId,
          MenuManagementScreen.uniflexVendorId);

      await tester.pumpWidget(_app(
          const VendorProductsScreen(vendor: _partnerVendor),
          overrides: _menuOverrides(admin, _menu)));
      await tester.pumpAndSettle();
      expect(find.byType(VendorMenuManager), findsOneWidget);
      expect(
          tester
              .widget<VendorMenuManager>(find.byType(VendorMenuManager))
              .vendorId,
          'partner-1');
      expect(find.text('Mama Put — Menu'), findsOneWidget);
    });

    testWidgets('items sit in the right section; empty sections still show',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(const MenuManagementScreen(),
          overrides: _menuOverrides(_FakeAdmin(), _menu)));
      await tester.pumpAndSettle();
      expect(find.text('Meals (2)'), findsOneWidget);
      expect(find.text('Proteins / Toppings (1)'), findsOneWidget);
      expect(find.text('Drinks (1)'), findsOneWidget);
      expect(find.text('Others (1)'), findsOneWidget);
      // Each section has its own Add.
      for (final s in MenuSection.values) {
        expect(find.byKey(ValueKey('add-${s.name}')), findsOneWidget);
      }

      // A vendor with only drinks: the other three sections say so.
      await tester.pumpWidget(_app(const MenuManagementScreen(),
          overrides: _menuOverrides(_FakeAdmin(),
              [_product('d1', 'Zobo', section: 'drinks', sub: null)])));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('empty-meals')), findsOneWidget);
      expect(find.byKey(const ValueKey('empty-drinks')), findsNothing);
    });

    for (final c in [
      (MenuSection.meals, 'food', 'meal', true),
      (MenuSection.proteins, 'food', 'protein_topping', true),
      (MenuSection.drinks, 'drinks', null, false),
      (MenuSection.others, 'others', null, false),
    ]) {
      testWidgets(
          '"+ Add" in ${c.$1.label} pre-selects it (no category choice)',
          (tester) async {
        final admin = _FakeAdmin();
        await tester.pumpWidget(_app(
            const VendorProductsScreen(vendor: _partnerVendor),
            overrides: _menuOverrides(admin, const [])));
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byKey(ValueKey('add-${c.$1.name}')));
        await tester.tap(find.byKey(ValueKey('add-${c.$1.name}')));
        await tester.pumpAndSettle();

        expect(find.text('Adding to ${c.$1.label}'), findsOneWidget);
        expect(find.byKey(const ValueKey('form-section-picker')), findsNothing);

        await tester.enterText(find.byType(TextFormField).at(0), 'Thing');
        await tester.enterText(find.byType(TextFormField).at(2), '750');
        await tester.ensureVisible(find.text('Add Item'));
        await tester.tap(find.text('Add Item'));
        await tester.pumpAndSettle();

        expect(admin.upserts, hasLength(1));
        final saved = admin.upserts.single;
        expect(saved['vendorId'], 'partner-1');
        expect(saved['section'], c.$2);
        expect(saved['foodSubsection'], c.$3);
        expect(saved['requiresPack'], c.$4);
        expect(saved['basePrice'], 750.0);
      });
    }

    testWidgets('availability switch changes ONLY availability',
        (tester) async {
      final admin = _FakeAdmin();
      await tester.pumpWidget(_app(
          const VendorProductsScreen(vendor: _partnerVendor),
          overrides: _menuOverrides(admin, _menu)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('switch-d1')));
      await tester.pumpAndSettle();
      expect(admin.availability, [('d1', false)]);
      expect(admin.upserts, isEmpty); // no full re-save → section can't be lost
    });

    testWidgets('delete asks first, then hides the item', (tester) async {
      final admin = _FakeAdmin();
      await tester.pumpWidget(_app(const MenuManagementScreen(),
          overrides: _menuOverrides(admin, _menu)));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove').last);
      await tester.pumpAndSettle();
      expect(admin.deleted, isEmpty); // still waiting for the confirm
      await tester.tap(find.descendant(
          of: find.byType(AppDialog), matching: find.text('Remove')));
      await tester.pumpAndSettle();
      expect(admin.deleted, ['m1']);
    });
  });

  // ── 2. Support ─────────────────────────────────────────────────────────
  group('Support: names', () {
    final conv = SupportConversation(
      id: 'c1',
      studentId: 's1',
      status: 'open',
      lastMessagePreview: 'Where is my food?',
      studentUnreadCount: 0,
      adminUnreadCount: 1,
      createdAt: DateTime(2026, 11, 1),
    );

    List<Override> inboxOverrides() => [
          allConversationsProvider.overrideWith((ref) => Stream.value([conv])),
          adminProfileBasicsProvider.overrideWith((ref, key) async => {
                's1': const ProfileBasics(
                    id: 's1',
                    nickname: 'Ada',
                    fullName: 'Adaeze Obi',
                    phone: '08031112222'),
              }),
        ];

    testWidgets('inbox row: nickname is the main name, full name underneath',
        (tester) async {
      await tester.pumpWidget(
          _app(const AdminSupportInboxScreen(), overrides: inboxOverrides()));
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsOneWidget);
      expect(find.byKey(const ValueKey('inbox-full-name')), findsOneWidget);
      expect(find.text('Adaeze Obi'), findsOneWidget);
      // Main name sits above the full name.
      expect(tester.getTopLeft(find.text('Ada')).dy,
          lessThan(tester.getTopLeft(find.text('Adaeze Obi')).dy));
    });

    for (final q in ['ada', 'obi', '0803111']) {
      testWidgets('inbox search finds the row by "$q"', (tester) async {
        await tester.pumpWidget(
            _app(const AdminSupportInboxScreen(), overrides: inboxOverrides()));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), q);
        await tester.pumpAndSettle();
        expect(find.text('Ada'), findsOneWidget);
      });
    }

    testWidgets('inbox search hides non-matching rows', (tester) async {
      await tester.pumpWidget(
          _app(const AdminSupportInboxScreen(), overrides: inboxOverrides()));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz-nobody');
      await tester.pumpAndSettle();
      expect(find.text('Ada'), findsNothing);
    });

    test('ProfileBasics: nickname first, full name second, no duplicates', () {
      const p = ProfileBasics(id: '1', nickname: 'Ada', fullName: 'Adaeze Obi');
      expect(p.displayName(), 'Ada');
      expect(p.secondaryName, 'Adaeze Obi');
      expect(const ProfileBasics(id: '1', fullName: 'Adaeze Obi').displayName(),
          'Adaeze Obi');
      expect(const ProfileBasics(id: '1', fullName: 'Adaeze Obi').secondaryName,
          isNull);
      expect(
          const ProfileBasics(id: '1', nickname: 'ada', fullName: 'Ada')
              .secondaryName,
          isNull);
      expect(const ProfileBasics(id: '1').displayName('Student'), 'Student');
      expect(profileIdsKey(['b', null, 'a', 'b', ' ']), 'a,b');
    });
  });

  group('Support: Help & Support choice', () {
    Future<void> pumpOptions(
      WidgetTester tester, {
      required String? number,
      String? orderShortId,
      Future<bool> Function(Uri)? launcher,
    }) async {
      await tester.pumpWidget(_app(
        SupportOptionsScreen(
          orderShortId: orderShortId,
          launcher: launcher,
          liveChatBuilder: (_) =>
              const Scaffold(body: Text('LIVE CHAT SCREEN')),
        ),
        overrides: [
          supportWhatsappProvider.overrideWith((ref) async => number),
          currentProfileProvider.overrideWith((ref) async => _profile()),
        ],
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('no number set → no choice screen, straight to live chat',
        (tester) async {
      await pumpOptions(tester, number: null);
      expect(find.text('LIVE CHAT SCREEN'), findsOneWidget);
      expect(find.byKey(const ValueKey('option-whatsapp')), findsNothing);
    });

    testWidgets('number could not be loaded → live chat (WhatsApp hidden)',
        (tester) async {
      await tester.pumpWidget(_app(
        SupportOptionsScreen(
          liveChatBuilder: (_) =>
              const Scaffold(body: Text('LIVE CHAT SCREEN')),
        ),
        overrides: [
          supportWhatsappProvider
              .overrideWith((ref) async => throw Exception('x')),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.text('LIVE CHAT SCREEN'), findsOneWidget);
    });

    testWidgets(
        'number set → both options; WhatsApp opens the right wa.me link',
        (tester) async {
      final opened = <Uri>[];
      await pumpOptions(tester, number: '2348031234567', launcher: (u) async {
        opened.add(u);
        return true;
      });
      expect(find.byKey(const ValueKey('option-live-chat')), findsOneWidget);
      expect(find.byKey(const ValueKey('option-whatsapp')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('option-whatsapp')));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(opened.single.host, 'wa.me');
      expect(opened.single.path, '/2348031234567');
      expect(opened.single.queryParameters['text'], 'Hi, this is Ada.');
    });

    testWidgets('from an order the message names the short order id',
        (tester) async {
      final opened = <Uri>[];
      await pumpOptions(tester, number: '2348031234567', orderShortId: 'AB12CD',
          launcher: (u) async {
        opened.add(u);
        return true;
      });
      await tester.tap(find.byKey(const ValueKey('option-whatsapp')));
      await tester.pumpAndSettle();
      expect(opened.single.queryParameters['text'],
          'Hi, this is Ada. Order #AB12CD.');
    });

    testWidgets('Live chat option opens the live chat', (tester) async {
      await pumpOptions(tester, number: '2348031234567');
      await tester.tap(find.byKey(const ValueKey('option-live-chat')));
      await tester.pumpAndSettle();
      expect(find.text('LIVE CHAT SCREEN'), findsOneWidget);
    });

    testWidgets('WhatsApp that cannot open shows a friendly note, no crash',
        (tester) async {
      await pumpOptions(tester,
          number: '2348031234567', launcher: (_) async => false);
      await tester.tap(find.byKey(const ValueKey('option-whatsapp')));
      await tester.pump();
      expect(find.textContaining("Couldn't open WhatsApp"), findsOneWidget);
    });

    test('phone normalising: 0803…, +234803…, spaces, junk', () {
      expect(normalizeNigerianPhone('08031234567'), '2348031234567');
      expect(normalizeNigerianPhone('0803 123 4567'), '2348031234567');
      expect(normalizeNigerianPhone('0803-123-4567'), '2348031234567');
      expect(normalizeNigerianPhone('+2348031234567'), '2348031234567');
      expect(normalizeNigerianPhone('+234 803 123 4567'), '2348031234567');
      expect(normalizeNigerianPhone('2348031234567'), '2348031234567');
      expect(normalizeNigerianPhone(''), isNull);
      expect(normalizeNigerianPhone('abc'), isNull);
      expect(normalizeNigerianPhone('0803123'), isNull);
      expect(normalizeNigerianPhone('+1 415 555 0100'), isNull);
    });

    test('wa.me link builder', () {
      final u = buildSupportWhatsappUri(digits: '2348031234567', name: 'Ada');
      expect(u.toString(), startsWith('https://wa.me/2348031234567?text='));
      expect(u.queryParameters['text'], 'Hi, this is Ada.');
      expect(
          buildSupportWhatsappUri(digits: '1', name: '  ', orderShortId: '#X1')
              .queryParameters['text'],
          'Hi, this is a Uniflex student. Order #X1.');
    });

    test('Support settings validator: empty ok, bad rejected, friendly error',
        () {
      expect(validateWhatsappNumber(''), isNull);
      expect(validateWhatsappNumber('0803 123 4567'), isNull);
      expect(validateWhatsappNumber('+234 803 123 4567'), isNull);
      expect(validateWhatsappNumber('12345'), isNotNull);
      expect(AppErrorMapper.map(Exception('P0001 INVALID_PHONE')),
          isNot(contains('INVALID_PHONE')));
    });
  });

  // ── 3. Rider name ──────────────────────────────────────────────────────
  group('Rider name on Admin cards', () {
    test('waiting before accept, name after, fallback only if name missing',
        () {
      expect(riderLineText(null, null), 'Waiting for rider');
      expect(riderLineText(null, 'Tunde'), 'Waiting for rider');
      expect(riderLineText('r1', 'Tunde'), 'Rider: Tunde');
      expect(riderLineText('r1', null), 'Rider assigned');
      expect(riderLineText('r1', '  '), 'Rider assigned');
    });
  });

  // ── 4. Dashboard / analytics ───────────────────────────────────────────
  group('Dashboard & analytics views', () {
    final stats = <String, dynamic>{
      'orders_today': 7,
      'pending_count': 2,
      'completed_today': 3,
      'cancelled_today': 2,
      'fees_today': 1370,
      'fees_week': 4000,
      'fees_month': 12000.5,
      'food_today': 3600,
      'food_week': 9000,
      'food_month': 40000,
    };

    testWidgets('dashboard shows the four counts and TWO separate money cards',
        (tester) async {
      await tester.pumpWidget(_app(Scaffold(
          body:
              SingleChildScrollView(child: DashboardStatsView(stats: stats)))));
      expect(find.text('Orders today'), findsOneWidget);
      expect(find.text('Pending / in progress'), findsOneWidget);
      expect(find.text('Completed today'), findsOneWidget);
      expect(find.text('Cancelled today'), findsOneWidget);
      expect(find.text('Fees collected'), findsOneWidget);
      expect(find.text('Food payments'), findsOneWidget);
      expect(find.text('₦1,370'), findsOneWidget);
      expect(find.text('₦3,600'), findsOneWidget);
      // Never summed into a single "revenue" figure.
      expect(find.text('₦4,970'), findsNothing);
      expect(find.textContaining('Revenue'), findsNothing);
    });

    test('naira() formatting and tolerant number reading', () {
      expect(naira(1370), '₦1,370');
      expect(naira(0), '₦0');
      expect(naira(1234567.4), '₦1,234,567');
      expect(statNum({'a': '12'}, 'a'), 12);
      expect(statNum({}, 'a'), 0);
    });

    testWidgets('analytics: periods, completion rate, top items, riders, users',
        (tester) async {
      _tall(tester);
      final data = <String, dynamic>{
        ...stats,
        'orders_week': 20,
        'orders_month': 60,
        'completed_week': 15,
        'completed_month': 45,
        'cancelled_week': 3,
        'cancelled_month': 5,
        'completion_rate': 90.0,
        'by_status': {'completed': 45, 'cancelled': 5, 'placed': 10},
        'top_items': [
          {'name': 'Jollof Rice', 'quantity': 31},
          {'name': 'Zobo', 'quantity': 12},
        ],
        'rider_performance': [
          {'rider_id': 'r1', 'name': 'Tunde', 'completed': 9},
        ],
        'users': {'students': 120, 'riders': 6},
      };
      await tester.pumpWidget(_app(Scaffold(
          body: SizedBox(height: 2400, child: AnalyticsView(data: data)))));
      await tester.pumpAndSettle();
      expect(find.text('90.0% completion rate'), findsOneWidget);
      expect(find.text('Jollof Rice'), findsOneWidget);
      expect(find.text('31 sold'), findsOneWidget);
      expect(find.text('Tunde'), findsOneWidget);
      expect(find.text('9 completed'), findsOneWidget);
      expect(find.text('120'), findsOneWidget);
      expect(find.text('Fees collected'), findsOneWidget);
      expect(find.text('Food payments'), findsOneWidget);
      expect(find.textContaining('Revenue'), findsNothing);
    });

    testWidgets('analytics with nothing finished says so (no 0% or NaN)',
        (tester) async {
      _tall(tester);
      await tester.pumpWidget(_app(const Scaffold(
          body: SizedBox(
              height: 2400,
              child: AnalyticsView(data: {'completion_rate': null})))));
      await tester.pumpAndSettle();
      expect(find.text('No finished orders yet this month'), findsOneWidget);
    });
  });

  group('Live refresh', () {
    testWidgets('RefreshOnTabVisible fires when its tab is switched TO',
        (tester) async {
      var calls = 0;
      final index = ValueNotifier<int>(0);
      await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, __) => AppNavShellScope(
            go: (_) {},
            currentIndex: i,
            child: RefreshOnTabVisible(
              tabIndex: 3,
              onVisible: () => calls++,
              child: const SizedBox(),
            ),
          ),
        ),
      ));
      expect(calls, 0); // building is not "opening"
      index.value = 1;
      await tester.pump();
      expect(calls, 0);
      index.value = 3;
      await tester.pump();
      await tester.pump();
      expect(calls, 1);
      index.value = 3; // no change
      await tester.pump();
      expect(calls, 1);
    });

    testWidgets(
        'an order change (after the first snapshot) triggers one refresh',
        (tester) async {
      final groups = StreamController<List<AdminDeliveryGroupRow>>();
      final errands = StreamController<List<AdminErrandRow>>();
      final kitchen = StreamController<List<KitchenOrder>>();
      var refreshes = 0;

      await tester.pumpWidget(ProviderScope(
        overrides: [
          adminDeliveryGroupsProvider.overrideWith((ref) => groups.stream),
          adminErrandOrdersProvider.overrideWith((ref) => errands.stream),
          kitchenOrdersProvider.overrideWith((ref) => kitchen.stream),
        ],
        child: MaterialApp(home: _LiveProbe(onRefresh: () => refreshes++)),
      ));

      groups.add(const []); // first snapshot — must NOT refresh
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(refreshes, 0);

      groups.add(const []); // a real change
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(refreshes, 1);

      // A burst collapses into one refresh.
      groups.add(const []);
      groups.add(const []);
      groups.add(const []);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(refreshes, 2);

      await tester.pumpWidget(const SizedBox());
      // (Not awaited: closing a controller nobody listens to never completes.)
      unawaited(groups.close());
      unawaited(errands.close());
      unawaited(kitchen.close());
    });
  });

  // ── 5. Ads ─────────────────────────────────────────────────────────────
  group('Ad links', () {
    test('normalising: bare domain gets https, only http(s) allowed', () {
      expect(normalizeAdLink('example.com/promo'), 'https://example.com/promo');
      expect(normalizeAdLink(' https://example.com '), 'https://example.com');
      expect(normalizeAdLink('http://example.com'), 'http://example.com');
      expect(
          normalizeAdLink('example.com:8080/x'), 'https://example.com:8080/x');
      expect(normalizeAdLink(''), isNull);
      expect(normalizeAdLink(null), isNull);
      expect(normalizeAdLink('javascript:alert(1)'), isNull);
      expect(normalizeAdLink('ftp://example.com'), isNull);
      expect(normalizeAdLink('mailto:a@b.com'), isNull);
      expect(normalizeAdLink('not a link'), isNull);
      expect(normalizeAdLink('https://'), isNull);
      expect(normalizeAdLink('localhost'), isNull);
    });

    test('validator: empty fine, nonsense gets a friendly message', () {
      expect(validateAdLink(''), isNull);
      expect(validateAdLink('example.com'), isNull);
      expect(validateAdLink('javascript:x'), contains('valid web address'));
    });

    test(
        'Advertisement.hasLink: existing url ads keep it; bad/old types never throw',
        () {
      expect(_ad('a', type: AdLinkType.url, link: 'https://x.com').hasLink,
          isTrue);
      expect(_ad('a', type: AdLinkType.url, link: 'x.com').webLink,
          'https://x.com');
      expect(_ad('a').hasLink, isFalse);
      expect(_ad('a', type: AdLinkType.url, link: '').hasLink, isFalse);
      expect(_ad('a', type: AdLinkType.url, link: 'javascript:1').hasLink,
          isFalse);
      // old vendor/wallet rows come back as `none` — their value is an id.
      expect(
          Advertisement.fromMap({
            'id': '1',
            'title': 't',
            'link_type': 'vendor',
            'link_value': 'some-vendor-id',
          }).hasLink,
          isFalse);
    });
  });

  group('Ad popup', () {
    Future<void> open(WidgetTester tester, Advertisement ad,
        {AdLinkLauncher? launcher}) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAdPopup(context, ad, launcher: launcher),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'shows the whole image (contain), centred, under 85% of the screen',
        (tester) async {
      await open(tester, _ad('a', image: 'https://img.invalid/a.png'));
      final image =
          tester.widget<Image>(find.byKey(const ValueKey('ad-popup-image')));
      expect(image.fit, BoxFit.contain);

      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      final box = tester.getRect(find.byKey(const ValueKey('ad-popup')));
      expect(box.width, lessThanOrEqualTo(screen.width * 0.85 + 0.5));
      expect(box.height, lessThanOrEqualTo(screen.height * 0.85 + 0.5));
      expect((box.center.dx - screen.width / 2).abs(), lessThan(1));
    });

    testWidgets('X closes it', (tester) async {
      await open(tester, _ad('a', image: 'https://img.invalid/a.png'));
      await tester.tap(find.byKey(const ValueKey('ad-popup-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ad-popup')), findsNothing);
    });

    testWidgets('tapping outside closes it', (tester) async {
      await open(tester, _ad('a', image: 'https://img.invalid/a.png'));
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ad-popup')), findsNothing);
    });

    testWidgets('no link → no Visit button', (tester) async {
      await open(tester, _ad('a', image: 'https://img.invalid/a.png'));
      expect(find.byKey(const ValueKey('ad-popup-visit')), findsNothing);
    });

    testWidgets('a malformed link → no Visit button and no crash',
        (tester) async {
      await open(
          tester,
          _ad('a',
              image: 'https://img.invalid/a.png',
              type: AdLinkType.url,
              link: 'javascript:alert(1)'));
      expect(find.byKey(const ValueKey('ad-popup-visit')), findsNothing);
    });

    testWidgets('link → Visit opens it externally; popup stays open',
        (tester) async {
      final opened = <Uri>[];
      await open(
        tester,
        _ad('a',
            image: 'https://img.invalid/a.png',
            type: AdLinkType.url,
            link: 'example.com/deal'),
        launcher: (u) async {
          opened.add(u);
          return true;
        },
      );
      expect(find.byKey(const ValueKey('ad-popup-visit')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ad-popup-visit')));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://example.com/deal');
      expect(find.byKey(const ValueKey('ad-popup')), findsOneWidget);
    });

    testWidgets('an ad without an image still opens (shows its text)',
        (tester) async {
      await open(tester, _ad('a'));
      expect(find.byKey(const ValueKey('ad-popup')), findsOneWidget);
      expect(find.text('Ad a'), findsWidgets);
    });
  });

  group('Ad carousel', () {
    Future<void> pump(WidgetTester tester, List<Advertisement> ads,
        {void Function(Advertisement)? onTap}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdCarousel(ads: ads, onTap: onTap ?? (_) {}),
        ),
      ));
      await tester.pump();
    }

    // The dot is 16 wide when active, 6 when not (plus a 6 margin each).
    double dotWidth(WidgetTester tester, int i) =>
        tester.getSize(find.byKey(ValueKey('ad-dot-$i'))).width - 6;

    testWidgets('moves by itself every 5 s over ~0.8 s, and loops',
        (tester) async {
      await pump(tester, [_ad('a'), _ad('b'), _ad('c')]);
      expect(dotWidth(tester, 0), 16);

      await tester.pump(const Duration(seconds: 4));
      expect(dotWidth(tester, 0), 16); // not yet

      await tester.pump(const Duration(seconds: 1)); // 5 s: slide starts
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500)); // slide done
      await tester.pump(const Duration(milliseconds: 300)); // dot animation
      expect(dotWidth(tester, 1), 16);
      expect(dotWidth(tester, 0), 6);

      // two more advances → back to the first (loops)
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 900));
        await tester.pump(const Duration(milliseconds: 300));
      }
      expect(dotWidth(tester, 0), 16);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pauses while touched, resumes after release', (tester) async {
      await pump(tester, [_ad('a'), _ad('b')]);
      final gesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('ad-pager'))));
      await tester.pump(const Duration(seconds: 12));
      expect(dotWidth(tester, 0), 16); // finger down → no movement

      await gesture.up();
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pump(const Duration(milliseconds: 300));
      expect(dotWidth(tester, 1), 16);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a single ad stays put: no pager, no dots, no timer',
        (tester) async {
      await pump(tester, [_ad('only')]);
      await tester.pump(const Duration(seconds: 30));
      expect(find.byKey(const ValueKey('ad-pager')), findsNothing);
      expect(find.byKey(const ValueKey('ad-dot-0')), findsNothing);
      expect(find.text('Ad only'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // would fail if a timer leaked
    });

    testWidgets('every ad is tappable (always opens the popup)',
        (tester) async {
      final tapped = <String>[];
      await pump(tester, [_ad('a'), _ad('b')], onTap: (a) => tapped.add(a.id));
      await tester.tap(find.text('Ad a'));
      expect(tapped, ['a']);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ── 6. Referral display ────────────────────────────────────────────────
  group('Referral on the student side', () {
    testWidgets('"Refer a student" says to contact Admin; button opens support',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(
          MaterialApp(home: ReferAStudentScreen(openSupport: () => opened++)));
      expect(
          find.text('Contact Admin to get a referral code.'), findsOneWidget);
      expect(find.textContaining('₦'), findsNothing);
      await tester.tap(find.text('Contact support'));
      expect(opened, 1);
    });

    test(
        'no student file shows a referral code, amounts, counts or leaderboard',
        () {
      final banned = <String>[
        'Your referral code',
        'ReferralScreen',
        'referralLeaderboardProvider',
        'myReferralCodeProvider',
        'get_referral_leaderboard',
        'my_referral_code',
        'getReferralLeaderboard',
        'getMyReferralCode',
        '.referralCode',
        '.referralCount',
        'Referral code copied',
        'Earn rewards for every friend',
      ];
      final offenders = <String>[];
      for (final f in Directory('lib/student')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final text = f.readAsStringSync();
        for (final b in banned) {
          if (text.contains(b)) offenders.add('${f.path}: $b');
        }
      }
      expect(offenders, isEmpty);
    });

    test('the referral-related badges are hidden from the student', () {
      final text =
          File('lib/student/profile/badges_screen.dart').readAsStringSync();
      expect(text.contains("'Refer your first friend'"), isFalse);
      expect(text.contains("'Refer 10 friends'"), isFalse);
    });
  });
}

/// A tiny host for [StatsLiveRefresh].
class _LiveProbe extends ConsumerStatefulWidget {
  const _LiveProbe({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  ConsumerState<_LiveProbe> createState() => _LiveProbeState();
}

class _LiveProbeState extends ConsumerState<_LiveProbe>
    with StatsLiveRefresh<_LiveProbe> {
  @override
  Widget build(BuildContext context) {
    listenForOrderChanges(widget.onRefresh);
    return const SizedBox();
  }
}
