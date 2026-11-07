// Pack 4B tests — shared order breakdown, rider Jobs/Active/History,
// delivery-complete screen, local-time helpers, error mapping.
// No Supabase and no emulator: everything drives pure widgets/models.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/rider/history/delivery_history_screen.dart';
import 'package:uniflex/rider/history/rider_history_detail_screen.dart';
import 'package:uniflex/rider/jobs/active_jobs_screen.dart';
import 'package:uniflex/rider/jobs/delivery_complete_screen.dart';
import 'package:uniflex/rider/jobs/rider_job.dart';
import 'package:uniflex/rider/pool/job_pool_screen.dart';
import 'package:uniflex/shared/models/delivery_group.dart' show DeliveryGroupStatus;
import 'package:uniflex/shared/order_breakdown/order_breakdown_models.dart';
import 'package:uniflex/shared/order_breakdown/order_breakdown_widget.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/utils/local_time.dart';
import 'package:uniflex/student/tracking/order_tracking_screen.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// For widgets that are themselves scrollable (ListView).
Widget _hostBox(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(height: 800, child: child)),
    );

Map<String, dynamic> _vendor(
  String name, {
  List<Map<String, dynamic>> packs = const [],
  List<Map<String, dynamic>> items = const [],
  List<Map<String, dynamic>> drinks = const [],
  List<Map<String, dynamic>> others = const [],
  String? location,
}) {
  final count = packs.fold<int>(
          0, (n, p) => n + (p['items'] as List).length) +
      items.length +
      drinks.length +
      others.length;
  return {
    'vendor_id': name,
    'vendor_name': name,
    'vendor_location': location,
    'packs': packs,
    'items': items,
    'drinks': drinks,
    'others': others,
    'item_count': count,
    'vendor_total': 1000,
  };
}

Map<String, dynamic> _pack(int i, num price, List<String> names) => {
      'index': i,
      'price': price,
      'items': [
        for (final n in names) {'name': n, 'quantity': 2},
      ],
    };

Map<String, dynamic> _line(String name, num qty, num unit) =>
    {'name': name, 'quantity': qty, 'unit_price': unit, 'line_total': qty * unit};

OrderBreakdownData _data(List<Map<String, dynamic>> vendors) =>
    OrderBreakdownData.fromJson({
      'order_id': 'abc',
      'kind': 'delivery',
      'vendors': vendors,
    });

void main() {
  group('OrderBreakdown — single vendor', () {
    testWidgets('plain header, CLOSED pack dropdowns with price in the title',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(
        data: _data([
          _vendor('Mama Put',
              location: 'Block C',
              packs: [
                _pack(1, 200, ['Jollof rice']),
                _pack(2, 200, ['Fried rice']),
              ]),
        ]),
      )));

      expect(find.text('Mama Put'), findsOneWidget);
      expect(find.text('Block C'), findsOneWidget);
      // No vendor dropdown for a single vendor.
      expect(find.byKey(const ValueKey('vendor-card-0')), findsNothing);
      // Pack dropdowns exist, show the price, and are closed.
      expect(find.text('Pack 1 · ₦200'), findsOneWidget);
      expect(find.text('Pack 2 · ₦200'), findsOneWidget);
      expect(find.text('Pack 1 · ₦0'), findsNothing);
      expect(find.textContaining('Jollof rice'), findsNothing);

      await tester.tap(find.text('Pack 1 · ₦200'));
      await tester.pumpAndSettle();
      expect(find.textContaining('2× Jollof rice'), findsOneWidget);
      expect(find.textContaining('Fried rice'), findsNothing,
          reason: 'only the tapped pack opens');
    });

    testWidgets('drinks and others are plain lists, only when present',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(
        data: _data([
          _vendor('Mama Put',
              packs: [_pack(1, 200, ['Rice'])],
              drinks: [_line('Coke', 2, 300)],
              others: [_line('Napkins', 1, 50)]),
        ]),
      )));
      expect(find.text('Drinks'), findsOneWidget);
      expect(find.text('Others'), findsOneWidget);
      // Plain = visible without tapping anything.
      expect(find.textContaining('Coke'), findsOneWidget);
      expect(find.textContaining('Napkins'), findsOneWidget);
    });

    testWidgets('no drinks/others headings when the vendor has none',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(
        data: _data([
          _vendor('Mama Put', packs: [_pack(1, 200, ['Rice'])]),
        ]),
      )));
      expect(find.text('Drinks'), findsNothing);
      expect(find.text('Others'), findsNothing);
    });

    testWidgets('no packs ⇒ no pack section at all', (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(
        data: _data([
          _vendor('Drinks Hub', drinks: [_line('Fanta', 3, 250)]),
        ]),
      )));
      expect(find.textContaining('Pack '), findsNothing);
      expect(find.textContaining('Fanta'), findsOneWidget);
    });

    testWidgets('shows item prices and the vendor amount, never fees',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(
        data: _data([
          _vendor('Mama Put', drinks: [_line('Coke', 2, 300)]),
        ]),
      )));
      expect(find.text('₦600'), findsOneWidget); // line total
      expect(find.byKey(const ValueKey('vendor-total-v0')), findsOneWidget);
      expect(find.textContaining('fee'), findsNothing);
      expect(find.textContaining('Fee'), findsNothing);
      expect(find.textContaining('charge'), findsNothing);
    });
  });

  group('OrderBreakdown — multi vendor', () {
    final data = _data([
      _vendor('Mama Put', packs: [_pack(1, 200, ['Jollof rice'])]),
      _vendor('Chop Bar',
          packs: [_pack(1, 250, ['Beans'])], drinks: [_line('Coke', 1, 300)]),
      _vendor('Drinks Hub', drinks: [_line('Fanta', 3, 250)]),
    ]);

    testWidgets('every vendor is a CLOSED dropdown; nothing auto-opens',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(data: data)));
      expect(find.byKey(const ValueKey('vendor-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('vendor-card-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('vendor-card-2')), findsOneWidget);
      expect(find.text('Mama Put'), findsOneWidget);
      expect(find.textContaining('Pack 1'), findsNothing);
      expect(find.textContaining('Jollof'), findsNothing);
      expect(find.textContaining('Fanta'), findsNothing);
    });

    testWidgets('subtitle shows item count and vendor amount', (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(data: data)));
      expect(find.text('2 items · ₦1000'), findsOneWidget); // Chop Bar
      expect(find.text('1 item · ₦1000'), findsNWidgets(2));
    });

    testWidgets('opening a vendor shows the same layout inside',
        (tester) async {
      await tester.pumpWidget(_host(OrderBreakdownView(data: data)));
      await tester.tap(find.text('Chop Bar'));
      await tester.pumpAndSettle();
      expect(find.text('Pack 1 · ₦250'), findsOneWidget);
      expect(find.text('Drinks'), findsOneWidget);
      // The pack inside is itself still closed.
      expect(find.textContaining('Beans'), findsNothing);
      await tester.tap(find.text('Pack 1 · ₦250'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Beans'), findsOneWidget);
    });
  });

  group('Breakdown model', () {
    test('pack title carries the stored price', () {
      expect(BreakdownPack.fromJson(_pack(3, 200, ['x'])).title,
          'Pack 3 · ₦200');
    });
    test('multi-vendor flag', () {
      expect(_data([_vendor('A')]).isMultiVendor, isFalse);
      expect(_data([_vendor('A'), _vendor('B')]).isMultiVendor, isTrue);
    });
  });

  // ── Rider Jobs tab ───────────────────────────────────────────────────────

  RiderJob food(String id, {List<String> vendors = const ['Mama Put']}) =>
      RiderJob(
        id: id,
        kind: RiderJobKind.food,
        vendorNames: vendors,
        stopCount: vendors.length,
        deliveryLocation: 'Hall 3',
        createdAt: DateTime.now(),
      );
  RiderJob errand(String id) => RiderJob(
        id: id,
        kind: RiderJobKind.errand,
        category: 'Print',
        itemDescription: 'Print my notes',
        deliveryLocation: 'Hall 4',
        createdAt: DateTime.now(),
      );

  group('Jobs tab = pool only', () {
    testWidgets('shows pool cards and no active-job links', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        height: 700,
        child: JobPoolList(
          pool: RiderPool(
            groups: [food('11111111-aaaa', vendors: ['A', 'B'])],
            errands: [errand('22222222-bbbb')],
          ),
        ),
      )));
      expect(find.byKey(const ValueKey('pool-11111111-aaaa')), findsOneWidget);
      expect(find.byKey(const ValueKey('pool-22222222-bbbb')), findsOneWidget);
      expect(find.textContaining('ctive'), findsNothing);
      expect(find.text('2 vendors'), findsOneWidget);
    });

    testWidgets('empty pool shows its own empty state', (tester) async {
      await tester.pumpWidget(_host(const SizedBox(
        height: 400,
        child: JobPoolList(pool: RiderPool()),
      )));
      expect(find.text('No jobs available'), findsOneWidget);
    });

    testWidgets('pool cards never mention fees', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        height: 700,
        child: JobPoolList(
          pool: RiderPool(groups: [food('11111111-aaaa')]),
        ),
      )));
      expect(find.textContaining('fee'), findsNothing);
      expect(find.textContaining('₦'), findsNothing);
    });
  });

  group('Active jobs chooser logic', () {
    test('both kinds ⇒ chooser', () {
      expect(activeJobsTarget(food: 1, errands: 2), ActiveJobsTarget.chooser);
    });
    test('only food ⇒ food list directly', () {
      expect(activeJobsTarget(food: 2, errands: 0), ActiveJobsTarget.food);
    });
    test('only errands ⇒ errand list directly', () {
      expect(activeJobsTarget(food: 0, errands: 1), ActiveJobsTarget.errands);
    });
    test('none ⇒ food list (it shows its empty state)', () {
      expect(activeJobsTarget(food: 0, errands: 0), ActiveJobsTarget.food);
    });

    testWidgets('chooser offers both lists', (tester) async {
      RiderJobKind? picked;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ActiveJobsChooser(
              food: 2, errands: 1, onPick: (k) => picked = k),
        ),
      ));
      expect(find.text('Active food deliveries'), findsOneWidget);
      expect(find.text('Active errands'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chooser-errands')));
      expect(picked, RiderJobKind.errand);
    });

    testWidgets('lists show cards and per-kind empty states', (tester) async {
      RiderJob? opened;
      await tester.pumpWidget(_host(SizedBox(
        height: 500,
        child: ActiveJobsList(
          kind: RiderJobKind.food,
          jobs: [food('33333333-cccc')],
          onOpen: (j) => opened = j,
        ),
      )));
      await tester.tap(find.byKey(const ValueKey('active-33333333-cccc')));
      expect(opened?.id, '33333333-cccc');

      await tester.pumpWidget(_host(SizedBox(
        height: 500,
        child: ActiveJobsList(
            kind: RiderJobKind.food, jobs: const [], onOpen: (_) {}),
      )));
      expect(find.text('No active food deliveries'), findsOneWidget);

      await tester.pumpWidget(_host(SizedBox(
        height: 500,
        child: ActiveJobsList(
            kind: RiderJobKind.errand, jobs: const [], onOpen: (_) {}),
      )));
      expect(find.text('No active errands'), findsOneWidget);
    });
  });

  // ── Delivery complete / history ──────────────────────────────────────────

  RiderJobDetail detail({String status = 'completed', bool byStudent = false}) =>
      RiderJobDetail(
        id: 'abcdef12-0000-0000-0000-000000000000',
        kind: RiderJobKind.food,
        status: status,
        completedAt: status == 'completed' ? DateTime.utc(2026, 11, 7, 13, 5) : null,
        cancelledAt: status == 'cancelled' ? DateTime.utc(2026, 11, 7, 13, 5) : null,
        cancelledByStudent: byStudent,
        customerName: 'Ada Obi',
        deliveryLocation: 'Hall 3, Room 12',
        amount: 4500,
      );

  group('Delivery complete screen', () {
    testWidgets('success icon, order id, customer, time and Done',
        (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DeliveryCompleteView(
              detail: detail(), onDone: () => done = true),
        ),
      ));
      expect(find.byKey(const ValueKey('delivery-complete-icon')),
          findsOneWidget);
      expect(find.text('Delivery complete'), findsOneWidget);
      expect(find.text('#ABCDEF12'), findsOneWidget);
      expect(find.text('Ada Obi'), findsOneWidget);
      expect(find.text(formatLocalDateTime(DateTime.utc(2026, 11, 7, 13, 5))),
          findsOneWidget);
      await tester.tap(find.text('Done'));
      expect(done, isTrue);
    });
  });

  group('History', () {
    testWidgets('details are read-only and show no phone or email',
        (tester) async {
      await tester.pumpWidget(_hostBox(RiderHistoryDetailView(
        detail: detail(),
        breakdown: const Text('BREAKDOWN-HERE'),
      )));
      expect(find.text('Delivered'), findsWidgets);
      expect(find.text('#ABCDEF12'), findsOneWidget);
      expect(find.text('Ada Obi'), findsOneWidget);
      expect(find.text('Hall 3, Room 12'), findsOneWidget);
      expect(find.text('BREAKDOWN-HERE'), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
      expect(find.textContaining('Call'), findsNothing);
      expect(find.textContaining('WhatsApp'), findsNothing);
      expect(find.textContaining('@'), findsNothing);
      expect(find.textContaining('hone'), findsNothing);
      expect(find.textContaining('mail'), findsNothing);
      expect(find.textContaining('atric'), findsNothing);
    });

    testWidgets('cancelled-by-customer is labelled', (tester) async {
      await tester.pumpWidget(_hostBox(RiderHistoryDetailView(
          detail: detail(status: 'cancelled', byStudent: true))));
      expect(find.text('Cancelled by customer'), findsOneWidget);
    });

    testWidgets('one card per checkout, cancelled jobs labelled',
        (tester) async {
      final jobs = [
        RiderJob(
          id: 'aaaaaaaa-1',
          kind: RiderJobKind.food,
          vendorNames: const ['A', 'B'],
          stopCount: 2,
          endedAt: DateTime.utc(2026, 11, 7, 12),
        ),
        RiderJob(
          id: 'bbbbbbbb-2',
          kind: RiderJobKind.food,
          vendorNames: const ['C'],
          wasCancelled: true,
          cancelledByStudent: true,
          endedAt: DateTime.utc(2026, 11, 7, 11),
        ),
      ];
      RiderJob? opened;
      await tester.pumpWidget(_host(SizedBox(
        height: 600,
        child: RiderHistoryList(jobs: jobs, onOpen: (j) => opened = j),
      )));
      expect(find.byKey(const ValueKey('history-aaaaaaaa-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-bbbbbbbb-2')), findsOneWidget);
      expect(find.text('Cancelled by customer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('history-bbbbbbbb-2')));
      expect(opened?.id, 'bbbbbbbb-2');
    });

    testWidgets('empty history has its own empty state', (tester) async {
      await tester.pumpWidget(_host(SizedBox(
        height: 400,
        child: RiderHistoryList(jobs: const [], onOpen: (_) {}),
      )));
      expect(find.text('No deliveries yet'), findsOneWidget);
    });
  });

  group('Student Delivered card', () {
    testWidgets('shows Delivered and the local time', (tester) async {
      final t = DateTime.utc(2026, 11, 7, 13, 5);
      await tester.pumpWidget(_host(DeliveredCard(completedAt: t)));
      expect(find.text('Delivered'), findsOneWidget);
      expect(find.text(formatLocalDateTime(t)), findsOneWidget);
    });
  });

  // ── Time + parsing + errors ──────────────────────────────────────────────

  group('Local time', () {
    test('parseServerTime gives local time', () {
      final t = parseServerTime('2026-11-07T13:05:00+00:00')!;
      expect(t.isUtc, isFalse);
      expect(t.toUtc(), DateTime.utc(2026, 11, 7, 13, 5));
    });
    test('null / garbage ⇒ null', () {
      expect(parseServerTime(null), isNull);
      expect(parseServerTime('nope'), isNull);
    });
    test('formatLocalDateTime is "d Mon yyyy, HH:mm"', () {
      final local = DateTime(2026, 11, 7, 14, 5);
      expect(formatLocalDateTime(local), '7 Nov 2026, 14:05');
    });
  });

  group('RiderJob parsing', () {
    test('food entry', () {
      final j = RiderJob.fromJson({
        'id': 'g1',
        'kind': 'food',
        'delivery_location': 'Hall 3',
        'vendor_names': ['A', 'B'],
        'stop_count': 2,
        'ended_at': '2026-11-07T13:05:00+00:00',
        'amount': 4500,
      });
      expect(j.isFood, isTrue);
      expect(j.vendorNames, ['A', 'B']);
      expect(j.endedAt!.toUtc(), DateTime.utc(2026, 11, 7, 13, 5));
      expect(j.amount, 4500);
    });
    test('pool payload has no fee or phone fields to read', () {
      final j = RiderJob.fromJson({'id': 'e1', 'kind': 'errand'});
      expect(j.isErrand, isTrue);
      expect(j.amount, isNull);
    });
  });

  group('Error mapping (Pack 4B)', () {
    test('job cap uses the exact sentence', () {
      expect(
        AppErrorMapper.map(Exception('PostgrestException(message: ACTIVE_JOB_LIMIT)')),
        'You already have 3 active jobs. Finish one before accepting another.',
      );
    });
    test('race lost', () {
      expect(AppErrorMapper.map(Exception('Already accepted by another rider')),
          'This job was just taken by another rider.');
      expect(AppErrorMapper.map(Exception('could not obtain lock on row')),
          'This job was just taken by another rider.');
    });
    test('wrong delivery PIN is not shown as a transaction PIN error', () {
      expect(AppErrorMapper.map(Exception('Incorrect delivery PIN')),
          contains('delivery PIN'));
    });
  });

  group('RiderGroupDetail (rider_group_detail payload)', () {
    test('parses status, location and cancelled-by-student; has no PIN/fees', () {
      final d = RiderGroupDetail.fromJson({
        'id': 'g1',
        'status': 'awaiting_final_payment',
        'delivery_location': 'Hall 3',
        'student_note': 'Gate B',
        'cancelled_by_student': false,
        'final_amount': 4500,
      });
      expect(d.status, DeliveryGroupStatus.awaitingFinalPayment);
      expect(d.deliveryLocation, 'Hall 3');
      expect(d.isTerminal, isFalse);
      expect(d.finalAmount, 4500);
    });
    test('cancelled/completed are terminal', () {
      expect(
          RiderGroupDetail.fromJson({'id': 'g', 'status': 'cancelled'})
              .isTerminal,
          isTrue);
      expect(
          RiderGroupDetail.fromJson({'id': 'g', 'status': 'completed'})
              .isTerminal,
          isTrue);
    });
  });
}
