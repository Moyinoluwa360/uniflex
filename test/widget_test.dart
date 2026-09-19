// Smoke tests for the Phase 1 auth flow: the app boots to the splash
// screen, then — with no persisted session — lands on the Login screen,
// which is the only place Create Account is reachable from. These don't
// hit a real Supabase project: Supabase.initialize runs against a local,
// in-memory session store, so there is never a restored session and the
// only "backend" calls that would happen are none, since nothing here
// submits a form.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:uniflex/app.dart';

/// In-memory stand-in for both of Supabase's default (SharedPreferences-
/// backed) storages, so these tests never touch platform channels — only
/// [EmptyLocalStorage] is built into supabase_flutter, and that alone
/// isn't enough: the PKCE code-verifier storage defaults to
/// SharedPreferences too unless overridden separately.
class _InMemoryAsyncStorage extends GotrueAsyncStorage {
  final _store = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _store[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    _store[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async => _store.remove(key);
}

Future<void> _settleSplash(WidgetTester tester) async {
  // AuthGate holds the splash for a minimum stretch (900ms) even once
  // the (here, instantly-null) session/profile lookup resolves.
  await tester.pump(const Duration(milliseconds: 1000));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test-anon-key',
      authOptions: FlutterAuthClientOptions(
        localStorage: const EmptyLocalStorage(),
        pkceAsyncStorage: _InMemoryAsyncStorage(),
      ),
    );
  });

  testWidgets('shows the splash wordmark immediately on launch', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: UniflexApp()));

    expect(find.text('Uniflex'), findsOneWidget);
    expect(find.text('Log In'), findsNothing);

    // Drain AuthGate's pending "minimum splash time" timer so it doesn't
    // outlive the test.
    await _settleSplash(tester);
  });

  testWidgets('lands on Login when there is no session', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: UniflexApp()));
    await _settleSplash(tester);

    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
    // No self-signup path for Rider/Admin anywhere on this screen.
    expect(find.text('Continue as Rider'), findsNothing);
    expect(find.text('Continue as Admin'), findsNothing);
  });

  testWidgets('Create Account opens Step One with the three signup fields', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: UniflexApp()));
    await _settleSplash(tester);

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('Email address'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
  });

  testWidgets('Step One rejects a weak password before hitting the network', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: UniflexApp()));
    await _settleSplash(tester);

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email address').first,
      'student@run.edu.ng',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password').first,
      'short',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Phone number').first,
      '08012345678',
    );

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('At least 8 characters'), findsOneWidget);
  });
}
