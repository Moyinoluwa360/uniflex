// The previous person's cached data (e.g. wallet balance) must never show
// for the next account signed in on the same phone.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/theme/theme_mode_provider.dart';
import 'package:uniflex/user_session_scope.dart';

var _loads = 0;

/// Stands in for walletBalanceProvider: computed once, then cached.
final _cachedBalance = Provider<int>((ref) => ++_loads);

void main() {
  testWidgets(
      'switching or signing out drops every cached value; '
      'signing in from nobody keeps the screen; theme survives',
      (tester) async {
    _loads = 0;
    final users = StreamController<String?>();
    addTearDown(users.close);
    var cleared = 0;
    late WidgetRef seen;

    await tester.pumpWidget(UserSessionScope(
      initialUserId: 'A',
      userIdChanges: users.stream,
      onUserChanged: () async => cleared++,
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          seen = ref;
          return Text('balance ${ref.watch(_cachedBalance)}',
              textDirection: TextDirection.ltr);
        }),
      ),
    ));
    expect(find.text('balance 1'), findsOneWidget);
    seen.read(themeModeProvider.notifier).state = ThemeMode.dark;

    // A signs out → fresh scope.
    users.add(null);
    await tester.pumpAndSettle();
    expect(find.text('balance 2'), findsOneWidget);
    expect(cleared, 1);
    expect(seen.read(themeModeProvider), ThemeMode.dark);

    // Nobody → B (login / sign-up): no rebuild, so sign-up screens survive.
    users.add('B');
    await tester.pumpAndSettle();
    expect(find.text('balance 2'), findsOneWidget);
    expect(cleared, 1);

    // B → C directly (account switch without a sign-out event) → fresh.
    users.add('C');
    await tester.pumpAndSettle();
    expect(find.text('balance 3'), findsOneWidget);
    expect(cleared, 2);

    // Token refresh for the same user: nothing happens.
    users.add('C');
    await tester.pumpAndSettle();
    expect(find.text('balance 3'), findsOneWidget);
  });
}
