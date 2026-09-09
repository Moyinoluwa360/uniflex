// Smoke tests for the Phase 0 scaffold: the app boots, the mock role
// picker is the entry point, and each role choice routes to its own
// shell without leaking into another role's screen.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:uniflex/app.dart';

void main() {
  testWidgets('shows the mock role picker when no role is signed in', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: UniflexApp()),
    );

    expect(find.text('Uniflex'), findsOneWidget);
    expect(find.text('Continue as Student'), findsOneWidget);
    expect(find.text('Continue as Rider'), findsOneWidget);
    expect(find.text('Continue as Admin'), findsOneWidget);
  });

  testWidgets('routes to the Student shell after choosing Student', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: UniflexApp()),
    );

    await tester.tap(find.text('Continue as Student'));
    await tester.pumpAndSettle();

    expect(find.text('Student Home'), findsOneWidget);
    expect(find.text('Continue as Rider'), findsNothing);
  });

  testWidgets('routes to the Rider shell after choosing Rider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: UniflexApp()),
    );

    await tester.tap(find.text('Continue as Rider'));
    await tester.pumpAndSettle();

    expect(find.text('Rider Home'), findsOneWidget);
  });

  testWidgets('routes to the Admin shell after choosing Admin', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: UniflexApp()),
    );

    await tester.tap(find.text('Continue as Admin'));
    await tester.pumpAndSettle();

    expect(find.text('Admin Home'), findsOneWidget);
  });
}
