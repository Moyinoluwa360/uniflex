// Pack 6 tests — food gifting + the stuck-text-selection fix.
// No Supabase, no emulator: pure widgets, models and fake repositories.
// (The server rules are covered by supabase/pack_6_test.sql.)

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uniflex/rider/jobs/food_job_screen.dart';
import 'package:uniflex/rider/jobs/rider_job.dart';
import 'package:uniflex/rider/jobs/rider_job_card.dart';
import 'package:uniflex/rider/services/rider_providers.dart';
import 'package:uniflex/rider/services/rider_service.dart';
import 'package:uniflex/shared/models/cart_item.dart';
import 'package:uniflex/shared/models/delivery_group.dart';
import 'package:uniflex/shared/models/delivery_location.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_models.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_provider.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_widget.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/profile/profile_service.dart';
import 'package:uniflex/shared/services/settings/service_charge_provider.dart';
import 'package:uniflex/shared/services/wallet/wallet_providers.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/widgets/inputs/app_text_field.dart';
import 'package:uniflex/shared/widgets/inputs/keyboard_dismiss.dart';
import 'package:uniflex/student/gifts/gift_models.dart';
import 'package:uniflex/student/gifts/gift_received_screen.dart';
import 'package:uniflex/student/gifts/gift_repository.dart';
import 'package:uniflex/student/gifts/gifts_screen.dart';
import 'package:uniflex/student/notifications/notification_router.dart';
import 'package:uniflex/student/ordering/cart_provider.dart';
import 'package:uniflex/student/ordering/checkout_draft.dart';
import 'package:uniflex/student/ordering/checkout_screen.dart';
import 'package:uniflex/student/ordering/commitment_fee_screen.dart';
import 'package:uniflex/student/ordering/order_payment_repository.dart';
import 'package:uniflex/student/ordering/order_repository.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

const _loc = DeliveryLocation(
  id: 'loc-1',
  name: 'Engineering Hostel',
  price: 300,
  isActive: true,
  sortOrder: 0,
);

Vendor _vendor(String id, {bool uniflex = true}) => Vendor(
      id: id,
      name: 'Kitchen $id',
      description: '',
      isFeatured: uniflex,
      isActive: true,
      badgeLabel: 'Major',
      packPrice: 200,
    );

CartState _cartUniflex() {
  final v = _vendor('v1');
  return CartState(
    groups: {
      v.id: VendorCartGroup(
        vendor: v,
        items: [
          CartItem(
            product: Product(
              id: 'p1',
              vendorId: v.id,
              name: 'Jollof Rice',
              description: '',
              category: 'Meals',
              basePrice: 1500,
            ),
            quantity: 1,
          ),
        ],
      ),
    },
    lastModifiedAt: DateTime.now(),
  );
}

class _TestCart extends CartNotifier {
  _TestCart(this.initial);
  final CartState initial;
  @override
  CartState build() => initial;
}

class _FakePayRepo implements OrderPaymentRepository {
  CheckoutDraft? lastDraft;
  @override
  Future<PaidOrderResult> payDelivery({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  }) async {
    lastDraft = draft;
    return const PaidOrderResult(kind: 'delivery', orderId: 'x');
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _FakeGiftRepo implements GiftRepository {
  _FakeGiftRepo(this.answers);
  final Map<String, GiftLookupResult> answers;
  final List<String> asked = [];

  @override
  Future<GiftLookupResult> lookup(String email) async {
    asked.add(email);
    return answers[email] ?? const GiftLookupFailed('NOT_FOUND');
  }
}

const _ada = GiftRecipient(
  email: 'jay@gmail.com',
  nickname: 'Jay',
  maskedEmail: 'j***@gmail.com',
);

class _FakeProfile implements ProfileService {
  @override
  Future<bool> hasTransactionPin() async => true;
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

List<Override> _checkoutOverrides({
  required CartState cart,
  required _FakeGiftRepo gifts,
  _FakePayRepo? pay,
}) =>
    [
      cartProvider.overrideWith(() => _TestCart(cart)),
      giftRepositoryProvider.overrideWithValue(gifts),
      orderPaymentRepositoryProvider.overrideWithValue(pay ?? _FakePayRepo()),
      profileServiceProvider.overrideWithValue(_FakeProfile()),
      walletBalanceProvider.overrideWith((ref) async => 5000),
      walletInfoProvider.overrideWith((ref) async => null),
      walletTransactionsProvider.overrideWith((ref) async => []),
      serviceChargeProvider.overrideWith((ref) async => 30),
      deliveryLocationsProvider.overrideWith((ref) async => [_loc]),
      studentOrdersProvider.overrideWith((ref) => Stream.value(const [])),
      studentDeliveryGroupsProvider
          .overrideWith((ref) => Stream.value(const [])),
      groupByIdProvider.overrideWith((ref, id) => Stream.value(null)),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget home,
  List<Override> overrides,
) async {
  tester.view.physicalSize = const Size(900, 2800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(theme: AppTheme.light, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

Map<String, dynamic> _giftRow({
  String status = 'preparing',
  String? pin = '4821',
  String? message = 'Happy birthday!',
}) =>
    {
      'group_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'recipient_id': 'r1',
      'sender_nickname': 'Ada',
      'message': message,
      'status': status,
      'delivery_pin': pin,
      'delivery_location': 'Engineering Hostel',
      'location_details': 'Room 204',
      'created_at': '2026-11-07T10:00:00Z',
      // As the server stores it: the breakdown with every price removed.
      'items': {
        'order_id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'kind': 'delivery',
        'vendors': [
          {
            'vendor_id': 'v1',
            'vendor_name': 'Mama Tee',
            'vendor_location': 'Block A',
            'packs': [
              {
                'index': 1,
                'items': [
                  {'name': 'Jollof Rice', 'quantity': 2},
                ],
              },
            ],
            'items': [],
            'drinks': [
              {'name': 'Chapman', 'quantity': 1},
            ],
            'others': [],
            'item_count': 3,
          },
        ],
      },
    };

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // ═══ §3 stuck text-selection highlight ══════════════════════════════════
  group('text selection is released', () {
    Widget host(Widget child, {bool root = false}) => MaterialApp(
          scrollBehavior: const AppScrollBehavior(),
          builder: root ? (context, c) => TapOutsideUnfocus(child: c!) : null,
          home: Scaffold(body: child),
        );

    Future<void> select(
        WidgetTester tester, TextEditingController c, Finder field) async {
      await tester.tap(field);
      await tester.pump();
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      await tester.pump();
      expect(c.selection.isCollapsed, isFalse);
    }

    testWidgets('tapping outside the field drops focus and the selection',
        (tester) async {
      final c = TextEditingController(text: 'hello world');
      final node = FocusNode();
      await tester.pumpWidget(host(Column(children: [
        AppTextField(controller: c, focusNode: node),
        const Expanded(child: Center(child: Text('empty space'))),
      ])));
      await select(tester, c, find.byType(AppTextField));
      expect(node.hasFocus, isTrue);

      await tester.tap(find.text('empty space'));
      await tester.pump();

      expect(node.hasFocus, isFalse);
      expect(c.selection.isCollapsed, isTrue);
    });

    testWidgets(
        'CONTROL — root cause: a plain Flutter field keeps focus (and its '
        'highlight) when you touch elsewhere on a phone', (tester) async {
      final c = TextEditingController(text: 'hello world');
      final node = FocusNode();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            TextField(controller: c, focusNode: node),
            const Expanded(child: Center(child: Text('empty space'))),
          ]),
        ),
      ));
      await select(tester, c, find.byType(TextField));
      await tester.tap(find.text('empty space'));
      await tester.pump();
      expect(node.hasFocus, isTrue, reason: 'Flutter default on touch devices');
      expect(c.selection.isCollapsed, isFalse);
    });

    testWidgets('a button still works while a field is focused',
        (tester) async {
      final c = TextEditingController(text: 'hello world');
      final node = FocusNode();
      var pressed = 0;
      await tester.pumpWidget(host(Column(children: [
        AppTextField(controller: c, focusNode: node),
        ElevatedButton(onPressed: () => pressed++, child: const Text('Go')),
      ])));
      await select(tester, c, find.byType(AppTextField));

      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(pressed, 1);
      expect(node.hasFocus, isFalse);
      expect(c.selection.isCollapsed, isTrue);
    });

    testWidgets('losing focus any other way also clears the selection',
        (tester) async {
      final c = TextEditingController(text: 'hello world');
      final node = FocusNode();
      await tester
          .pumpWidget(host(AppTextField(controller: c, focusNode: node)));
      await select(tester, c, find.byType(AppTextField));

      node.unfocus(); // e.g. a route closing, a programmatic unfocus
      await tester.pump();

      expect(c.selection.isCollapsed, isTrue);
    });

    testWidgets('scrolling a form dismisses the field (app scroll behaviour)',
        (tester) async {
      final c = TextEditingController(text: 'hello world');
      final node = FocusNode();
      await tester.pumpWidget(host(SingleChildScrollView(
        child: Column(children: [
          AppTextField(controller: c, focusNode: node),
          const SizedBox(height: 2000),
        ]),
      )));
      await select(tester, c, find.byType(AppTextField));
      expect(node.hasFocus, isTrue);

      await tester.drag(
          find.byType(SingleChildScrollView), const Offset(0, -300));
      await tester.pump();

      expect(node.hasFocus, isFalse);
      expect(c.selection.isCollapsed, isTrue);
    });

    testWidgets('root: tapping empty screen unfocuses even a plain field',
        (tester) async {
      final node = FocusNode();
      await tester.pumpWidget(host(
        Column(children: [
          TextField(focusNode: node), // not the shared component
          const Expanded(child: SizedBox.expand()),
        ]),
        root: true,
      ));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(node.hasFocus, isTrue);

      await tester.tapAt(const Offset(400, 500));
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });

    test('no raw TextField/TextFormField is left outside the shared component',
        () {
      final raw = RegExp(r'(?<![A-Za-z])(TextField|TextFormField)\(');
      final offenders = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        if (f.path
            .replaceAll('\\', '/')
            .endsWith('inputs/app_text_field.dart')) {
          continue;
        }
        if (raw.hasMatch(f.readAsStringSync())) offenders.add(f.path);
      }
      expect(offenders, isEmpty);
    });
  });

  // ═══ Lookup result + friendly errors ════════════════════════════════════
  group('gift lookup', () {
    test('found: only nickname + masked email come through', () {
      final r = GiftLookupResult.fromMap(' jay@gmail.com ', {
        'ok': true,
        'nickname': 'Jay',
        'masked_email': 'j***@gmail.com',
      }) as GiftLookupFound;
      expect(r.recipient.nickname, 'Jay');
      expect(r.recipient.maskedEmail, 'j***@gmail.com');
      expect(r.recipient.email, 'jay@gmail.com');
    });

    test('unknown / self / rate-limited have friendly wording', () {
      String msg(String reason) =>
          (GiftLookupResult.fromMap('x', {'ok': false, 'reason': reason})
                  as GiftLookupFailed)
              .message;
      expect(msg('NOT_FOUND'), 'No student found with that email.');
      expect(msg('SELF'), contains('yourself'));
      expect(msg('RATE_LIMITED'), contains('Too many'));
      expect(AppErrorMapper.map('GIFT_SELF'), contains('yourself'));
      expect(AppErrorMapper.map('GIFT_RECIPIENT_NOT_FOUND'),
          'No student found with that email.');
      expect(AppErrorMapper.map('GIFT_MESSAGE_TOO_LONG'), contains('200'));
    });
  });

  // ═══ Checkout: the switch + Find + Change ═══════════════════════════════
  group('checkout', () {
    testWidgets('gift switch shows for delivery, not for pickup',
        (tester) async {
      await _pump(tester, const CheckoutScreen(),
          _checkoutOverrides(cart: _cartUniflex(), gifts: _FakeGiftRepo({})));

      // Delivery is the default.
      expect(find.text('Send as a gift'), findsOneWidget);

      await tester.tap(find.text('Pickup'));
      await tester.pumpAndSettle();
      expect(find.text('Send as a gift'), findsNothing);

      await tester.tap(find.text('Delivery'));
      await tester.pumpAndSettle();
      expect(find.text('Send as a gift'), findsOneWidget);
    });

    testWidgets('Find shows Nickname + masked email only; Change goes back',
        (tester) async {
      final repo =
          _FakeGiftRepo({'jay@gmail.com': const GiftLookupFound(_ada)});
      await _pump(tester, const CheckoutScreen(),
          _checkoutOverrides(cart: _cartUniflex(), gifts: repo));

      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, "Recipient's email"),
          'jay@gmail.com');
      await tester.tap(find.byKey(const ValueKey('gift-find')));
      await tester.pumpAndSettle();

      expect(repo.asked, ['jay@gmail.com']);
      expect(find.byKey(const ValueKey('gift-recipient')), findsOneWidget);
      expect(find.textContaining('Sending to:', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Jay', findRichText: true), findsWidgets);
      expect(find.textContaining('j***@gmail.com', findRichText: true),
          findsOneWidget);
      // The real address is not shown any more.
      expect(find.textContaining('jay@gmail.com', findRichText: true),
          findsNothing);

      await tester.tap(find.byKey(const ValueKey('gift-change')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gift-recipient')), findsNothing);
      expect(find.widgetWithText(TextFormField, "Recipient's email"),
          findsOneWidget);
    });

    testWidgets('unknown and self emails get the friendly line',
        (tester) async {
      final repo = _FakeGiftRepo({
        'me@gmail.com': const GiftLookupFailed('SELF'),
      });
      await _pump(tester, const CheckoutScreen(),
          _checkoutOverrides(cart: _cartUniflex(), gifts: repo));
      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();

      Future<void> find_(String email) async {
        await tester.enterText(
            find.widgetWithText(TextFormField, "Recipient's email"), email);
        await tester.tap(find.byKey(const ValueKey('gift-find')));
        await tester.pumpAndSettle();
      }

      await find_('nobody@gmail.com');
      expect(find.text('No student found with that email.'), findsOneWidget);
      await find_('me@gmail.com');
      expect(
          find.textContaining("can't send a gift to yourself"), findsOneWidget);
    });

    testWidgets('Continue is blocked until the recipient is found',
        (tester) async {
      await _pump(tester, const CheckoutScreen(),
          _checkoutOverrides(cart: _cartUniflex(), gifts: _FakeGiftRepo({})));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Engineering Hostel').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Location details'), 'Room 1');
      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Find the student'), findsOneWidget);
      expect(find.byType(CommitmentFeeScreen), findsNothing);
    });

    testWidgets('a found recipient reaches the payment page and the repo',
        (tester) async {
      final pay = _FakePayRepo();
      final repo =
          _FakeGiftRepo({'jay@gmail.com': const GiftLookupFound(_ada)});
      await _pump(tester, const CheckoutScreen(),
          _checkoutOverrides(cart: _cartUniflex(), gifts: repo, pay: pay));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Engineering Hostel').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Location details'), 'Room 1');
      await tester.tap(find.byKey(const ValueKey('gift-switch')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, "Recipient's email"),
          'jay@gmail.com');
      await tester.tap(find.byKey(const ValueKey('gift-find')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Gift message (optional)'),
          'Enjoy!');

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(CommitmentFeeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-pay-banner')), findsOneWidget);
      expect(find.textContaining('Jay'), findsWidgets);
    });

    test('only food DELIVERY can be a gift (pickup drops it)', () {
      final cart = _cartUniflex();
      final delivery = CheckoutDraft.fromCart(cart,
          isPickup: false,
          location: _loc,
          locationDetails: 'Room 1',
          giftRecipient: _ada,
          giftMessage: '  Enjoy  ');
      expect(delivery.isGift, isTrue);
      expect(delivery.giftMessage, 'Enjoy');

      final pickup = CheckoutDraft.fromCart(cart,
          isPickup: true, giftRecipient: _ada, giftMessage: 'x');
      expect(pickup.isGift, isFalse);
      expect(pickup.giftRecipient, isNull);
      expect(pickup.giftMessage, isNull);

      final plain =
          CheckoutDraft.fromCart(cart, isPickup: false, location: _loc);
      expect(plain.isGift, isFalse);
    });
  });

  // ═══ Recipient view ═════════════════════════════════════════════════════
  group('recipient view', () {
    Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('shows sender, message, items and PIN — no prices anywhere',
        (tester) async {
      tester.view.physicalSize = const Size(900, 3000);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final gift = GiftDelivery.fromMap(_giftRow());
      await tester.pumpWidget(host(GiftReceivedView(gift: gift)));
      await tester.pump();

      expect(find.text('Gift from Ada'), findsOneWidget);
      expect(find.textContaining('Happy birthday!'), findsOneWidget);
      expect(find.text('Being prepared'), findsWidgets);
      // the delivery PIN, digit by digit
      for (final d in '4821'.split('')) {
        expect(find.text(d), findsWidgets);
      }
      expect(find.byKey(const ValueKey('gift-pin-card')), findsOneWidget);

      // Items: the pack is closed by default; open it.
      expect(find.text('Pack 1'), findsOneWidget);
      await tester.tap(find.text('Pack 1'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jollof Rice'), findsOneWidget);
      expect(find.textContaining('Chapman'), findsOneWidget);

      // No money, anywhere on the screen.
      expect(find.textContaining('₦'), findsNothing);
      expect(find.textContaining('fee', findRichText: true), findsNothing);
      expect(find.textContaining('Vendor total'), findsNothing);
      // Nothing to pay / decline / cancel / edit.
      for (final word in ['Pay', 'Decline', 'Cancel order', 'Edit']) {
        expect(find.widgetWithText(ElevatedButton, word), findsNothing);
        expect(find.widgetWithText(FilledButton, word), findsNothing);
        expect(find.widgetWithText(OutlinedButton, word), findsNothing);
        expect(find.widgetWithText(TextButton, word), findsNothing);
      }
    });

    testWidgets('delivered / cancelled gifts no longer show the PIN',
        (tester) async {
      for (final s in ['delivered', 'cancelled']) {
        final gift = GiftDelivery.fromMap(_giftRow(status: s, pin: null));
        await tester.pumpWidget(host(GiftReceivedView(gift: gift)));
        await tester.pump();
        expect(find.byKey(const ValueKey('gift-pin-card')), findsNothing,
            reason: s);
      }
      final cancelled =
          GiftDelivery.fromMap(_giftRow(status: 'cancelled', pin: '4821'));
      await tester.pumpWidget(host(GiftReceivedView(gift: cancelled)));
      await tester.pump();
      expect(find.byKey(const ValueKey('gift-pin-card')), findsNothing);
      expect(find.byKey(const ValueKey('gift-cancelled')), findsOneWidget);
    });

    testWidgets('OrderBreakdown "no prices" mode vs normal mode',
        (tester) async {
      final data = OrderBreakdownData.fromJson({
        'order_id': 'o',
        'kind': 'delivery',
        'vendors': [
          {
            'vendor_id': 'v',
            'vendor_name': 'Mama Tee',
            'packs': [
              {
                'index': 1,
                'price': 200,
                'items': [
                  {'name': 'Rice', 'quantity': 1},
                ],
              },
            ],
            'items': [],
            'drinks': [
              {'name': 'Chapman', 'quantity': 2, 'line_total': 1000},
            ],
            'others': [],
            'item_count': 2,
            'vendor_total': 1200,
          },
        ],
      });

      await tester.pumpWidget(
          host(SingleChildScrollView(child: OrderBreakdownView(data: data))));
      expect(find.textContaining('₦'), findsWidgets);
      expect(find.text('Vendor total'), findsOneWidget);

      await tester.pumpWidget(host(SingleChildScrollView(
          child: OrderBreakdownView(data: data, showPrices: false))));
      await tester.pump();
      expect(find.textContaining('₦'), findsNothing);
      expect(find.text('Vendor total'), findsNothing);
      expect(find.text('Pack 1'), findsOneWidget);
    });

    test('the received-gift model has no money fields to leak', () {
      final src = File('lib/student/gifts/gift_models.dart').readAsStringSync();
      final cls = src.substring(src.indexOf('class GiftDelivery'));
      for (final word in [
        'amount',
        'price',
        'fee',
        'total',
        'wallet',
        'paid'
      ]) {
        expect(cls.toLowerCase().contains(word), isFalse, reason: word);
      }
    });

    test('gift notifications open the gift view, not the sender\'s order', () {
      for (final t in [
        'gift_received',
        'gift_on_the_way',
        'gift_delivered',
        'gift_cancelled'
      ]) {
        expect(
            NotificationTarget.fromPayload({'type': t, 'group_id': 'g'}).isGift,
            isTrue);
      }
      expect(
          NotificationTarget.fromPayload(
              {'type': 'order_status', 'group_id': 'g'}).isGift,
          isFalse);
    });
  });

  // ═══ Gifts screen + old Gift feature gone ═══════════════════════════════
  group('Gifts screen', () {
    DeliveryGroup sentGroup() => DeliveryGroup.fromMap({
          'id': '11111111-2222-3333-4444-555555555555',
          'student_id': 's1',
          'delivery_type': 'delivery',
          'status': 'out_for_delivery',
          'created_at': '2026-11-07T10:00:00Z',
          'is_gift': true,
          'gift_recipient_id': 'r1',
          'gift_recipient_nickname': 'Jay',
          'gift_message': 'Enjoy',
        });

    testWidgets('lists gifts sent and received, in two tabs', (tester) async {
      await _pump(tester, const GiftsScreen(), [
        studentDeliveryGroupsProvider
            .overrideWith((ref) => Stream.value([sentGroup()])),
        receivedGiftsProvider.overrideWith(
            (ref) => Stream.value([GiftDelivery.fromMap(_giftRow())])),
      ]);

      expect(find.text('Sent'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
      // Sent tab first: recipient nickname + status.
      expect(find.text('To Jay'), findsOneWidget);
      expect(find.text('Out for Delivery'), findsOneWidget);

      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      expect(find.text('Gift from Ada'), findsOneWidget);
      expect(find.text('Being prepared'), findsOneWidget);
    });

    testWidgets('empty states for both tabs', (tester) async {
      await _pump(tester, const GiftsScreen(), [
        studentDeliveryGroupsProvider.overrideWith((ref) => Stream.value([])),
        receivedGiftsProvider.overrideWith((ref) => Stream.value([])),
      ]);
      expect(find.text('No gifts sent yet'), findsOneWidget);
      await tester.tap(find.text('Received'));
      await tester.pumpAndSettle();
      expect(find.text('No gifts received yet'), findsOneWidget);
    });

    test('old Gift screen, menu entry, model and client code are gone', () {
      expect(
          File('lib/student/profile/gift_screen.dart').existsSync(), isFalse);
      expect(File('lib/shared/models/gift.dart').existsSync(), isFalse);
      final profile = File('lib/student/profile/student_profile_screen.dart')
          .readAsStringSync();
      expect(profile.contains('Send a Gift'), isFalse);
      expect(profile.contains('GiftScreen('), isFalse);
      expect(profile.contains("title: 'Gifts'"), isTrue);
      final service =
          File('lib/student/services/student_service.dart').readAsStringSync();
      expect(service.contains('send_gift'), isFalse);
      expect(service.contains('get_gifts'), isFalse);
    });
  });

  // ═══ Rider ══════════════════════════════════════════════════════════════
  group('rider', () {
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

    testWidgets('pool card is tagged GIFT only for gift jobs', (tester) async {
      Future<void> show(bool gift) async {
        await tester.pumpWidget(host(RiderJobCard(
          job: RiderJob.fromJson({
            'id': '11111111-2222-3333-4444-555555555555',
            'kind': 'food',
            'is_gift': gift,
            'status': 'commitment_paid',
            'delivery_location': 'Engineering Hostel',
          }),
          onTap: () {},
        )));
      }

      await show(true);
      expect(find.byKey(const ValueKey('gift-tag')), findsOneWidget);
      expect(find.text('GIFT'), findsOneWidget);
      await show(false);
      expect(find.byKey(const ValueKey('gift-tag')), findsNothing);
    });

    test('pool data carries no personal details', () {
      final job = RiderJob.fromJson({
        'id': 'a' * 8 + '-0000-0000-0000-000000000000',
        'kind': 'food',
        'is_gift': true,
      });
      expect(job.isGift, isTrue);
      // RiderJob has no phone / email / name / matric field at all.
      final src = File('lib/rider/jobs/rider_job.dart').readAsStringSync();
      final cls = src.substring(0, src.indexOf('class RiderPool'));
      // No FIELD for any of them (comments may mention the rule).
      final fields = RegExp(r'^\s*final [^;]*;', multiLine: true)
          .allMatches(cls)
          .map((m) => m.group(0)!.toLowerCase())
          .join('\n');
      for (final w in ['matric', 'email', 'phone']) {
        expect(fields.contains(w), isFalse, reason: w);
      }
    });

    testWidgets(
        'accepted gift: "Deliver to" and "Paid by", each with Call + WhatsApp',
        (tester) async {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Ada Obi',
        'nickname': 'Ada',
        'phone': '08031234567',
        'email': 'ada@x.com',
        'location_details': 'Room 204',
        'is_gift': true,
        'gift': {
          'recipient': {
            'full_name': 'Jay Bello',
            'nickname': 'Jay',
            'phone': '08099998888',
            'email': 'jay@x.com',
            'location_details': 'Room 204',
          },
          'sender': {
            'full_name': 'Ada Obi',
            'nickname': 'Ada',
            'phone': '08031234567',
            'email': 'ada@x.com',
          },
        },
      });
      expect(info.isGift, isTrue);
      await tester.pumpWidget(host(RiderCustomerCard(info: info)));
      await tester.pump();

      expect(find.text('Deliver to'), findsOneWidget);
      expect(find.text('Paid by'), findsOneWidget);
      expect(find.text('Jay Bello'), findsOneWidget);
      expect(find.text('Ada Obi'), findsOneWidget);
      expect(find.text('jay@x.com'), findsOneWidget);
      expect(find.text('ada@x.com'), findsOneWidget);
      expect(find.text('Call'), findsNWidgets(2));
      expect(find.text('WhatsApp'), findsNWidgets(2));
      expect(find.textContaining('Room 204'), findsWidgets);
      expect(find.byKey(const ValueKey('gift-pin-note')), findsOneWidget);
      expect(
          find.textContaining('Ask Jay for the delivery PIN'), findsOneWidget);
      // never a matric number
      expect(find.textContaining('matric', findRichText: true), findsNothing);
    });

    testWidgets('ordinary delivery keeps the single Customer card',
        (tester) async {
      final info = GroupCustomerInfo.fromMap({
        'full_name': 'Ada Obi',
        'phone': '08031234567',
      });
      expect(info.isGift, isFalse);
      await tester.pumpWidget(host(RiderCustomerCard(info: info)));
      await tester.pump();
      expect(find.text('Customer'), findsOneWidget);
      expect(find.text('Deliver to'), findsNothing);
      expect(find.text('Paid by'), findsNothing);
      expect(find.text('Call'), findsOneWidget);
    });

    testWidgets('before accepting, the job preview asks for NO customer info',
        (tester) async {
      var asked = 0;
      final job = RiderJob.fromJson({
        'id': '11111111-2222-3333-4444-555555555555',
        'kind': 'food',
        'is_gift': true,
        'delivery_location': 'Engineering Hostel',
      });
      await _pump(tester, FoodJobScreen.fromPool(job: job), [
        groupCustomerInfoProvider.overrideWith((ref, id) {
          asked++;
          throw StateError('must not be asked before accepting');
        }),
        orderBreakdownProvider.overrideWith((ref, id) async =>
            const OrderBreakdownData(
                orderId: 'o', kind: 'delivery', vendors: [])),
      ]);
      expect(asked, 0);
      expect(find.text('Deliver to'), findsNothing);
      expect(find.text('Paid by'), findsNothing);
      expect(find.text('Call'), findsNothing);
      expect(find.text('Accept Job'), findsOneWidget);
    });
  });
}
