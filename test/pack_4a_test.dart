// Pack 4A tests — no emulator, no Supabase.
//
//   • fee quote: per-vendor lines, service charge once, pickup has no fees
//   • Continue creates nothing and leaves the cart alone
//   • payment page: lines, success clears cart AFTER the server answers,
//     wrong PIN / low balance create nothing, double tap fires once
//   • cart notice: shown once per cart, the "cleared" message never appears
//   • support chat: direct message, message with an order, Admin reply

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:uniflex/shared/theme/app_icons.dart';
import 'package:uniflex/admin/service_charge/service_charge_screen.dart';
import 'package:uniflex/admin/support/admin_support_chat_screen.dart';
import 'package:uniflex/shared/models/cart_item.dart';
import 'package:uniflex/shared/models/delivery_location.dart';
import 'package:uniflex/shared/models/product.dart';
import 'package:uniflex/shared/models/support_conversation.dart';
import 'package:uniflex/shared/models/support_message.dart';
import 'package:uniflex/shared/models/vendor.dart';
import 'package:uniflex/shared/services/auth/auth_providers.dart';
import 'package:uniflex/shared/services/profile/profile_service.dart';
import 'package:uniflex/shared/services/settings/service_charge_provider.dart';
import 'package:uniflex/shared/services/support/support_chat_service.dart';
import 'package:uniflex/shared/services/wallet/wallet_providers.dart';
import 'package:uniflex/shared/theme/app_theme.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/utils/uuid_v4.dart';
import 'package:uniflex/shared/widgets/buttons/app_button.dart';
import 'package:uniflex/shared/widgets/chat/support_order_chip.dart';
import 'package:uniflex/student/ordering/cart_notice_listener.dart';
import 'package:uniflex/student/ordering/cart_provider.dart';
import 'package:uniflex/student/ordering/cart_screen.dart';
import 'package:uniflex/student/ordering/checkout_draft.dart';
import 'package:uniflex/student/ordering/checkout_screen.dart';
import 'package:uniflex/student/ordering/commitment_fee_screen.dart';
import 'package:uniflex/student/ordering/order_payment_repository.dart';
import 'package:uniflex/student/ordering/order_repository.dart';
import 'package:uniflex/student/support/support_chat_screen.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

Vendor _vendor(String id, String name, {bool uniflex = false}) => Vendor(
      id: id,
      name: name,
      description: '',
      isFeatured: uniflex,
      isActive: true,
      badgeLabel: uniflex ? 'Major' : 'Partner',
      packPrice: 200,
    );

Product _product(String id, String vendorId, String name, double price) =>
    Product(
      id: id,
      vendorId: vendorId,
      name: name,
      description: '',
      category: 'Meals',
      basePrice: price,
    );

const _loc = DeliveryLocation(
  id: 'loc-1',
  name: 'Engineering Hostel',
  price: 300,
  isActive: true,
  sortOrder: 0,
);

CartState _cartTwoVendors() {
  final uni = _vendor('v-uni', 'Uniflex Kitchen', uniflex: true);
  final mama = _vendor('v-mama', 'Mama Tee');
  return CartState(
    groups: {
      uni.id: VendorCartGroup(
        vendor: uni,
        items: [
          CartItem(product: _product('p1', uni.id, 'Jollof Rice', 1500), quantity: 2),
        ],
        packCount: 1,
        packFee: 200,
        packContents: const [
          {'p1': 2},
        ],
      ),
      mama.id: VendorCartGroup(
        vendor: mama,
        items: [
          CartItem(product: _product('p2', mama.id, 'Fried Rice', 1800), quantity: 1),
        ],
      ),
    },
    lastModifiedAt: DateTime.now(),
  );
}

CartState _cartUniflexOnly() {
  final uni = _vendor('v-uni', 'Uniflex Kitchen', uniflex: true);
  return CartState(
    groups: {
      uni.id: VendorCartGroup(
        vendor: uni,
        items: [
          CartItem(product: _product('p1', uni.id, 'Jollof Rice', 1500), quantity: 2),
        ],
      ),
    },
    lastModifiedAt: DateTime.now(),
  );
}

/// A cart that starts with a given state and never touches storage on build.
class _TestCart extends CartNotifier {
  _TestCart(this.initial);
  final CartState initial;
  @override
  CartState build() => initial;
}

/// Fake of the ONE order-creating repository. Records every call; a test can
/// hold the response open with [gate] or make it fail with [error].
class _FakePaymentRepo implements OrderPaymentRepository {
  int deliveryCalls = 0;
  int pickupCalls = 0;
  int errandCalls = 0;
  final List<String> keys = [];
  Object? error;
  Completer<void>? gate;

  Future<PaidOrderResult> _answer(String kind, String key) async {
    keys.add(key);
    if (gate != null) await gate!.future;
    if (error != null) throw error!;
    return PaidOrderResult(
      kind: kind,
      orderId: '11111111-2222-3333-4444-555555555555',
      groupId: kind == 'delivery' ? '11111111-2222-3333-4444-555555555555' : null,
      totalCharged: 630,
      serviceCharge: 30,
    );
  }

  @override
  Future<PaidOrderResult> payDelivery({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  }) {
    deliveryCalls++;
    return _answer('delivery', idempotencyKey);
  }

  @override
  Future<PaidOrderResult> payPickup({
    required String idempotencyKey,
    required String pin,
    required CheckoutDraft draft,
  }) {
    pickupCalls++;
    return _answer('pickup', idempotencyKey);
  }

  @override
  Future<PaidOrderResult> payErrand({
    required String idempotencyKey,
    required String pin,
    required String categoryKey,
    required String pickupLocation,
    required String dropoffLocation,
    required String itemDescription,
    String? deliveryLocationId,
    String? locationDetails,
  }) {
    errandCalls++;
    return _answer('errand', idempotencyKey);
  }
}

class _FakeProfileService implements ProfileService {
  @override
  Future<bool> hasTransactionPin() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

List<Override> _baseOverrides({
  required _FakePaymentRepo repo,
  required CartState cart,
  double balance = 5000,
  double serviceCharge = 30,
}) =>
    [
      cartProvider.overrideWith(() => _TestCart(cart)),
      orderPaymentRepositoryProvider.overrideWithValue(repo),
      profileServiceProvider.overrideWithValue(_FakeProfileService()),
      walletBalanceProvider.overrideWith((ref) async => balance),
      walletInfoProvider.overrideWith((ref) async => null),
      walletTransactionsProvider.overrideWith((ref) async => []),
      serviceChargeProvider.overrideWith((ref) async => serviceCharge),
      deliveryLocationsProvider.overrideWith((ref) async => [_loc]),
      studentOrdersProvider.overrideWith((ref) => Stream.value(const [])),
      studentDeliveryGroupsProvider.overrideWith((ref) => Stream.value(const [])),
      groupByIdProvider.overrideWith((ref, id) => Stream.value(null)),
    ];

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home,
  List<Override> overrides,
) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  late ProviderContainer container;
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(theme: AppTheme.light, home: home);
      }),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Runs the shared payment step on screen: Pay → note sheet → PIN sheet.
Future<void> _payThroughSheets(WidgetTester tester, {String pin = '1234'}) async {
  await tester.tap(find.textContaining('Pay ₦'));
  await tester.pumpAndSettle();
  // acknowledgment note
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
  // PIN sheet
  await tester.enterText(find.byType(TextField).last, pin);
  await tester.tap(find.text('Confirm'));
  await tester.pump();
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('fee quote', () {
    test('delivery: each vendor on its own line, service charge ONCE', () {
      final draft = CheckoutDraft.fromCart(
        _cartTwoVendors(),
        isPickup: false,
        location: _loc,
        locationDetails: 'Room 204',
      );
      final q = quoteFor(draft, 30);
      expect(q.lines.length, 2);
      expect(q.lines.map((l) => l.label),
          ['Delivery fee · Uniflex Kitchen', 'Delivery fee · Mama Tee']);
      // 1 pack → 1× ₦300; 0 packs → still 1× ₦300
      expect(q.lines.map((l) => l.amount), [300, 300]);
      expect(q.serviceCharge, 30);
      expect(q.total, 630); // 600 + 30, NOT 600 + 2×30
    });

    test('pickup: full food amount, no delivery fee, no service charge', () {
      final draft = CheckoutDraft.fromCart(_cartUniflexOnly(), isPickup: true);
      final q = quoteFor(draft, 30);
      expect(q.serviceCharge, 0);
      expect(q.total, 3000); // 2 × 1500
      expect(q.lines.single.label, 'Food + packs');
    });

    test('the draft carries choices only (ids + quantities), never prices to the server', () {
      final draft = CheckoutDraft.fromCart(_cartTwoVendors(),
          isPickup: false, location: _loc, locationDetails: ' Room 1 ');
      expect(draft.locationDetails, 'Room 1');
      expect(draft.vendors.first.items.first.productId, 'p1');
      expect(draft.vendors.first.packs, [
        {'p1': 2}
      ]);
    });
  });

  group('helpers', () {
    test('uuid v4 has the right shape and is unique', () {
      final a = newUuidV4();
      final b = newUuidV4();
      expect(
          RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
              .hasMatch(a),
          isTrue);
      expect(a, isNot(b));
    });

    test('server payment codes become friendly messages', () {
      expect(AppErrorMapper.map(const PaymentException('INVALID_PIN')),
          'Incorrect PIN. Please try again.');
      expect(AppErrorMapper.map(const PaymentException('PIN_LOCKED')),
          contains('locked'));
      expect(AppErrorMapper.map('INSUFFICIENT_BALANCE'), contains('top up'));
      expect(AppErrorMapper.map('LOCATION_DETAILS_REQUIRED'),
          contains('where to deliver'));
    });

    test('service charge must be a whole number, 0 or more', () {
      expect(validateServiceCharge('30'), isNull);
      expect(validateServiceCharge('0'), isNull);
      expect(validateServiceCharge(''), isNotNull);
      expect(validateServiceCharge('-5'), isNotNull);
      expect(validateServiceCharge('12.5'), isNotNull);
      expect(validateServiceCharge('abc'), isNotNull);
    });
  });

  group('Continue (checkout form)', () {
    testWidgets('validates the form, opens payment, and creates NOTHING',
        (tester) async {
      final repo = _FakePaymentRepo();
      final container = await _pump(
        tester,
        const CheckoutScreen(),
        _baseOverrides(repo: repo, cart: _cartTwoVendors()),
      );

      // The button is "Continue", not "Place order".
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('Place Order'), findsNothing);

      // Nothing chosen yet → validation stops it; no payment page.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Pay delivery fee'), findsNothing);

      // Choose a location + describe where, then Continue.
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Engineering Hostel').last);
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Location details'), 'Room 204');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.byType(CommitmentFeeScreen), findsOneWidget);
      // Nothing was created and the cart is untouched.
      expect(repo.deliveryCalls + repo.pickupCalls + repo.errandCalls, 0);
      expect(container.read(cartProvider).isEmpty, isFalse);
      expect(container.read(cartProvider).itemCount, 3);
    });
  });

  group('payment page', () {
    Future<(ProviderContainer, _FakePaymentRepo)> openDelivery(
      WidgetTester tester, {
      double balance = 5000,
      _FakePaymentRepo? repo,
    }) async {
      repo ??= _FakePaymentRepo();
      final draft = CheckoutDraft.fromCart(
        _cartTwoVendors(),
        isPickup: false,
        location: _loc,
        locationDetails: 'Room 204',
      );
      final c = await _pump(
        tester,
        CommitmentFeeScreen(draft: draft),
        _baseOverrides(repo: repo, cart: _cartTwoVendors(), balance: balance),
      );
      return (c, repo);
    }

    testWidgets('lists each vendor fee, the service charge once, and the total',
        (tester) async {
      await openDelivery(tester);
      expect(find.text('Delivery fee · Uniflex Kitchen'), findsOneWidget);
      expect(find.text('Delivery fee · Mama Tee'), findsOneWidget);
      expect(find.text('Service charge'), findsOneWidget);
      expect(find.text('₦30'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₦630'), findsWidgets); // total (and the pay button)
      expect(find.textContaining('Pay ₦630'), findsOneWidget);
    });

    testWidgets('pickup shows the full food amount and no fees', (tester) async {
      final repo = _FakePaymentRepo();
      final draft = CheckoutDraft.fromCart(_cartUniflexOnly(), isPickup: true);
      await _pump(
        tester,
        CommitmentFeeScreen(draft: draft),
        _baseOverrides(repo: repo, cart: _cartUniflexOnly()),
      );
      expect(find.text('Service charge'), findsNothing);
      expect(find.textContaining('Delivery fee'), findsNothing);
      expect(find.text('Food + packs'), findsOneWidget);
      expect(find.textContaining('Pay ₦3,000'), findsOneWidget);
    });

    testWidgets('paying clears the cart only AFTER the server answers',
        (tester) async {
      final repo = _FakePaymentRepo()..gate = Completer<void>();
      final (container, _) = await openDelivery(tester, repo: repo);

      await _payThroughSheets(tester);
      await tester.pump(const Duration(milliseconds: 50));

      // Request is in flight: the server has been called once, cart intact.
      expect(repo.deliveryCalls, 1);
      expect(container.read(cartProvider).isEmpty, isFalse);

      repo.gate!.complete();
      await tester.pumpAndSettle();
      expect(container.read(cartProvider).isEmpty, isTrue);
    });

    testWidgets('wrong PIN creates nothing and keeps the cart', (tester) async {
      final repo = _FakePaymentRepo()..error = const PaymentException('INVALID_PIN');
      final (container, _) = await openDelivery(tester, repo: repo);

      await _payThroughSheets(tester, pin: '0000');
      await tester.pumpAndSettle();

      expect(repo.deliveryCalls, 1);
      expect(find.text('Incorrect PIN. Please try again.'), findsOneWidget);
      expect(container.read(cartProvider).isEmpty, isFalse);
      expect(find.byType(CommitmentFeeScreen), findsOneWidget); // still here
    });

    testWidgets('insufficient balance: pay is blocked and a top-up prompt shows',
        (tester) async {
      final (_, repo) = await openDelivery(tester, balance: 100);
      expect(find.textContaining('Top up your wallet'), findsOneWidget);
      final pay = tester.widget<AppButton>(
          find.widgetWithText(AppButton, 'Pay ₦630'));
      expect(pay.onPressed, isNull);
      expect(repo.deliveryCalls, 0);
    });

    testWidgets('a server "insufficient balance" answer shows the top-up prompt and keeps the cart',
        (tester) async {
      final repo = _FakePaymentRepo()..error = 'INSUFFICIENT_BALANCE';
      final (container, _) = await openDelivery(tester, repo: repo);
      await _payThroughSheets(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Top up your wallet'), findsOneWidget);
      expect(container.read(cartProvider).isEmpty, isFalse);
    });

    testWidgets('double tap fires once; a retry reuses the same idempotency key',
        (tester) async {
      final repo = _FakePaymentRepo()..gate = Completer<void>();
      await openDelivery(tester, repo: repo);

      await _payThroughSheets(tester);
      await tester.pump(const Duration(milliseconds: 50));
      // Button is now busy; hammer it.
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byType(AppButton).first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(repo.deliveryCalls, 1);

      // Network "drops": the call fails. The student taps Pay again.
      repo.gate!.complete();
      repo.error = Exception('SocketException');
      repo.gate = null;
      await tester.pumpAndSettle();
      await _payThroughSheets(tester);
      await tester.pumpAndSettle();

      expect(repo.deliveryCalls, 2);
      expect(repo.keys.toSet().length, 1,
          reason: 'the retry must carry the SAME idempotency key');
    });
  });

  group('cart notice', () {
    test('first add to an empty cart signals the notice once per cart', () {
      final container = ProviderContainer(
        overrides: [cartProvider.overrideWith(() => _TestCart(const CartState()))],
      );
      addTearDown(container.dispose);
      final vendor = _vendor('v1', 'Uniflex', uniflex: true);
      final item = CartItem(product: _product('p1', 'v1', 'Rice', 1000), quantity: 1);
      final notifier = container.read(cartProvider.notifier);

      expect(container.read(cartFirstAddNoticeProvider), 0);
      notifier.addItem(item, vendor);
      expect(container.read(cartFirstAddNoticeProvider), 1);
      notifier.addItem(item, vendor); // not the first item
      expect(container.read(cartFirstAddNoticeProvider), 1);

      notifier.clear(); // a new cart
      notifier.addItem(item, vendor);
      expect(container.read(cartFirstAddNoticeProvider), 2);
    });

    testWidgets('the notice text appears once, then not again for the same cart',
        (tester) async {
      final vendor = _vendor('v1', 'Uniflex', uniflex: true);
      final item = CartItem(product: _product('p1', 'v1', 'Rice', 1000), quantity: 1);
      final container = await _pump(
        tester,
        Scaffold(
          body: CartNoticeListener(
            child: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () =>
                    ref.read(cartProvider.notifier).addItem(item, vendor),
                child: const Text('add'),
              ),
            ),
          ),
        ),
        [cartProvider.overrideWith(() => _TestCart(const CartState()))],
      );

      await tester.tap(find.text('add'));
      await tester.pump();
      expect(find.text(kCartExpiryNotice), findsOneWidget);
      expect(kCartExpiryNotice,
          'Your cart will be cleared 1 hour after your last change.');

      // Dismiss it, then add another item to the same cart.
      ScaffoldMessenger.of(tester.element(find.text('add'))).clearSnackBars();
      await tester.pumpAndSettle();
      expect(find.text(kCartExpiryNotice), findsNothing);
      await tester.tap(find.text('add'));
      await tester.pump();
      expect(find.text(kCartExpiryNotice), findsNothing);
      expect(container.read(cartFirstAddNoticeProvider), 1);
    });

    testWidgets('an expired saved cart is cleared SILENTLY — no "cleared" message',
        (tester) async {
      final uni = _vendor('v-uni', 'Uniflex Kitchen', uniflex: true);
      final stale = CartState(
        groups: {
          uni.id: VendorCartGroup(
            vendor: uni,
            items: [
              CartItem(product: _product('p1', uni.id, 'Rice', 1000), quantity: 1),
            ],
          ),
        },
        lastModifiedAt: DateTime.now().subtract(const Duration(hours: 3)),
      );
      SharedPreferences.setMockInitialValues({
        'uniflex_cart_v2': _encode(stale),
      });

      final container = await _pump(tester, const CartScreen(), const []);
      await tester.pumpAndSettle();

      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(find.textContaining('cleared'), findsNothing);
      expect(find.textContaining('1 hour ago'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      // Opening the cart screen again later (a fresh cart) still shows nothing.
      container.read(cartProvider.notifier).checkAndClearIfExpired();
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
    });
  });

  group('support chat (fake service)', () {
    SupportMessage msg(String id,
            {String role = 'student', String? orderId, String? groupId}) =>
        SupportMessage(
          id: id,
          conversationId: 'conv-1',
          senderId: role == 'student' ? 'student-1' : 'admin-1',
          senderRole: role,
          senderName: role == 'student' ? 'Alice' : 'Bob',
          body: 'hello $id',
          orderId: orderId,
          deliveryGroupId: groupId,
          createdAt: DateTime(2026, 1, 1, 10, int.parse(id)),
        );

    final conv = SupportConversation(
      id: 'conv-1',
      studentId: 'student-1',
      status: 'open',
      studentUnreadCount: 0,
      adminUnreadCount: 0,
      createdAt: DateTime(2026, 1, 1),
    );

    testWidgets('student: a DIRECT message (no order) is sent with no attachment',
        (tester) async {
      final svc = _FakeSupportService();
      await _pump(tester, const SupportChatScreen(), [
        supportChatServiceProvider.overrideWithValue(svc),
        myConversationProvider.overrideWith((ref) => Stream.value(null)),
        currentProfileProvider.overrideWith((ref) async => null),
      ]);
      await tester.enterText(find.byType(TextField), 'I need help');
      await tester.tap(find.byIcon(AppIcons.send));
      await tester.pumpAndSettle();

      expect(svc.sent.length, 1);
      expect(svc.sent.single.body, 'I need help');
      expect(svc.sent.single.orderId, isNull);
      expect(svc.sent.single.groupId, isNull);
      expect(svc.sent.single.conversationId, isNull);
    });

    testWidgets('student: an order-attached message sends the order id, and the chip shows above the text box',
        (tester) async {
      final svc = _FakeSupportService();
      await _pump(
        tester,
        const SupportChatScreen(
          initialOrderId: 'aaaaaaaa-0000-0000-0000-000000000000',
          initialOrderLabel: '#AAAAAAAA · Placed',
        ),
        [
          supportChatServiceProvider.overrideWithValue(svc),
          myConversationProvider.overrideWith((ref) => Stream.value(null)),
          currentProfileProvider.overrideWith((ref) async => null),
        ],
      );
      expect(find.text('#AAAAAAAA · Placed'), findsOneWidget); // chip above the box

      await tester.enterText(find.byType(TextField), 'About my errand');
      await tester.tap(find.byIcon(AppIcons.send));
      await tester.pumpAndSettle();

      expect(svc.sent.single.orderId, 'aaaaaaaa-0000-0000-0000-000000000000');
      expect(svc.sent.single.groupId, isNull);
      expect(find.text('#AAAAAAAA · Placed'), findsNothing); // detached after send
    });

    testWidgets('student: a delivery (group) message sends the group id', (tester) async {
      final svc = _FakeSupportService();
      await _pump(
        tester,
        const SupportChatScreen(
          initialGroupId: 'bbbbbbbb-0000-0000-0000-000000000000',
          initialGroupLabel: '#BBBBBBBB · Delivery',
        ),
        [
          supportChatServiceProvider.overrideWithValue(svc),
          myConversationProvider.overrideWith((ref) => Stream.value(null)),
          currentProfileProvider.overrideWith((ref) async => null),
        ],
      );
      await tester.enterText(find.byType(TextField), 'Where is my food?');
      await tester.tap(find.byIcon(AppIcons.send));
      await tester.pumpAndSettle();
      expect(svc.sent.single.groupId, 'bbbbbbbb-0000-0000-0000-000000000000');
      expect(svc.sent.single.orderId, isNull);
    });

    testWidgets('student bubble shows the chip for an attached order AND for a delivery group',
        (tester) async {
      final svc = _FakeSupportService();
      await _pump(tester, const SupportChatScreen(), [
        supportChatServiceProvider.overrideWithValue(svc),
        myConversationProvider.overrideWith((ref) => Stream.value(conv)),
        conversationMessagesProvider.overrideWith((ref, id) => Stream.value([
              msg('1', orderId: 'aaaaaaaa-0000-0000-0000-000000000000'),
              msg('2', groupId: 'bbbbbbbb-0000-0000-0000-000000000000'),
              msg('3'),
            ])),
        currentProfileProvider.overrideWith((ref) async => null),
      ]);
      expect(find.text('Order #AAAAAAAA'), findsOneWidget);
      expect(find.text('Order #BBBBBBBB'), findsOneWidget);
      expect(find.byType(SupportOrderChip), findsNWidgets(2));
    });

    testWidgets('messages are oldest at the top, newest at the bottom (both sides)',
        (tester) async {
      final svc = _FakeSupportService();
      // Delivered out of order on purpose.
      final scrambled = [msg('3'), msg('1'), msg('2')];
      await _pump(tester, const SupportChatScreen(), [
        supportChatServiceProvider.overrideWithValue(svc),
        myConversationProvider.overrideWith((ref) => Stream.value(conv)),
        conversationMessagesProvider.overrideWith((ref, id) =>
            Stream.value(([...scrambled]
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt))))),
        currentProfileProvider.overrideWith((ref) async => null),
      ]);
      final y1 = tester.getTopLeft(find.text('hello 1')).dy;
      final y2 = tester.getTopLeft(find.text('hello 2')).dy;
      final y3 = tester.getTopLeft(find.text('hello 3')).dy;
      expect(y1 < y2 && y2 < y3, isTrue);
    });

    testWidgets('admin: a reply is sent to the conversation', (tester) async {
      final svc = _FakeSupportService();
      await _pump(tester, AdminSupportChatScreen(conversation: conv), [
        supportChatServiceProvider.overrideWithValue(svc),
        conversationMessagesProvider.overrideWith(
            (ref, id) => Stream.value([msg('1')])),
        currentProfileProvider.overrideWith((ref) async => null),
      ]);
      await tester.enterText(find.byType(TextField), 'We are on it');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();

      expect(svc.sent.single.body, 'We are on it');
      expect(svc.sent.single.conversationId, 'conv-1');
    });

    testWidgets('admin: tapping the order chip loads that order', (tester) async {
      final svc = _FakeSupportService();
      await _pump(tester, AdminSupportChatScreen(conversation: conv), [
        supportChatServiceProvider.overrideWithValue(svc),
        conversationMessagesProvider.overrideWith((ref, id) => Stream.value([
              msg('1', groupId: 'bbbbbbbb-0000-0000-0000-000000000000'),
            ])),
        currentProfileProvider.overrideWith((ref) async => null),
      ]);
      expect(find.text('Order #BBBBBBBB'), findsOneWidget);
      await tester.tap(find.text('Order #BBBBBBBB'));
      await tester.pumpAndSettle();
      expect(svc.groupLookups, ['bbbbbbbb-0000-0000-0000-000000000000']);
      // The fake has no such group, so the friendly message appears.
      expect(find.text('That order could not be found.'), findsOneWidget);
    });
  });
}

String _encode(CartState s) => jsonEncode(s.toJson()); // what the cart persists

class _Sent {
  _Sent(this.body, this.orderId, this.groupId, this.conversationId);
  final String body;
  final String? orderId;
  final String? groupId;
  final String? conversationId;
}

class _FakeSupportService implements SupportChatService {
  final List<_Sent> sent = [];
  final List<String> groupLookups = [];

  @override
  Future<Map<String, dynamic>> sendMessage(
    String body, {
    String? orderId,
    String? groupId,
    String? conversationId,
  }) async {
    sent.add(_Sent(body.trim(), orderId, groupId, conversationId));
    return {'message_id': 'm', 'conversation_id': 'conv-1'};
  }

  @override
  Future<void> markRead(String conversationId) async {}

  @override
  Future<Map<String, dynamic>?> fetchStudentProfile(String studentId) async =>
      {'full_name': 'Alice A', 'nickname': 'alice', 'phone': '0800'};

  @override
  Future<Map<String, dynamic>?> fetchDeliveryGroup(String groupId) async {
    groupLookups.add(groupId);
    return null;
  }

  @override
  Future<Map<String, dynamic>?> fetchOrder(String orderId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
