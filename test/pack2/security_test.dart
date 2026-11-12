// Pack 2 — security guards that can be checked without a device or the
// live database. The database rules themselves are proven in
// supabase/pack2_security_hardening_test.sql (33 checks, rolled back).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/utils/app_error_mapper.dart';
import 'package:uniflex/shared/utils/rpc_result.dart';

String _read(String p) => File(p).readAsStringSync();

/// Names / prefixes that must never be inside the bundled `.env`.
final _forbidden = RegExp(
  r'^(SUPABASE_SERVICE_ROLE_KEY|SUPABASE_SECRET_KEY|TERMII_API_KEY|'
  r'PAYSTACK_SECRET_KEY|FIREBASE_SERVICE_ACCOUNT)|sb_secret_|sk_(live|test)_',
  multiLine: true,
  caseSensitive: false,
);

void main() {
  group('S-10 no server secret is bundled into the app', () {
    test('the only bundled config file is .env', () {
      final pubspec = _read('pubspec.yaml');
      final assets = RegExp(r'^\s+- (\S+)$', multiLine: true)
          .allMatches(pubspec.split('fonts:').first.split('assets:').last)
          .map((m) => m.group(1))
          .toList();
      expect(assets, ['.env']);
    });

    test('the local .env (if present) holds no server-side secret', () {
      final f = File('.env');
      if (!f.existsSync()) return; // CI writes it; Codemagic checks it.
      final hits = _forbidden
          .allMatches(f.readAsStringSync())
          .map((m) => m.group(0))
          .toList();
      expect(hits, isEmpty,
          reason: 'Move these to .env.tooling or Edge Function secrets '
              'and rotate them: $hits');
    });

    test('.env.example is placeholder-only', () {
      expect(_forbidden.hasMatch(_read('.env.example')), isFalse);
    });

    test('Codemagic refuses a .env with a server secret before building', () {
      final cm = _read('codemagic.yaml');
      final write = cm.indexOf('ENV_FILE_CONTENTS" >');
      final guard = cm.indexOf('Refuse server secrets in the bundled .env');
      final build = cm.indexOf('flutter build ipa');
      expect(write, greaterThan(0));
      expect(guard, greaterThan(write));
      expect(build, greaterThan(guard));
      expect(cm.contains('sb_secret_'), isTrue);
    });

    test('Dart never reads a server key', () {
      final cfg = _read('lib/shared/config/env_config.dart');
      expect(cfg.contains('SECRET'), isFalse);
      expect(cfg.contains('SERVICE_ROLE'), isFalse);
    });
  });

  group('S-04 PIN errors returned by the server are shown, never "success"', () {
    test('throwIfRpcError throws on {"error": …} and passes data through', () {
      expect(() => throwIfRpcError({'error': 'INVALID_PIN'}),
          throwsA(isA<RpcErrorException>()));
      expect(throwIfRpcError({'balance_after': 10}), {'balance_after': 10});
      expect(throwIfRpcError(null), isNull);
      expect(throwIfRpcError({'error': ''}), {'error': ''});
    });

    test('the error maps to the friendly PIN messages', () {
      String msg(String code) {
        try {
          throwIfRpcError({'error': code});
        } catch (e) {
          return AppErrorMapper.map(e);
        }
        return '';
      }

      expect(msg('INVALID_PIN'), 'Incorrect PIN. Please try again.');
      expect(msg('PIN_LOCKED'), contains('locked for 15 minutes'));
      expect(msg('PIN_NOT_SET'), 'Please set a transaction PIN first.');
    });

    test('both final-payment calls check the returned error', () {
      final src = _read('lib/student/tracking/order_tracking_screen.dart');
      expect(
          RegExp(r"throwIfRpcError\(await client\.rpc\('pay_final_amount'")
              .hasMatch(src),
          isTrue);
      expect(
          RegExp(r"throwIfRpcError\(await client\.rpc\('pay_group_final_amount'")
              .hasMatch(src),
          isTrue);
    });

    test('change-PIN handles a returned INVALID_CURRENT_PIN / PIN_LOCKED', () {
      final src = _read('lib/shared/services/profile/profile_service.dart');
      expect(src.contains("error == 'INVALID_CURRENT_PIN'"), isTrue);
      expect(src.contains("error == 'PIN_LOCKED'"), isTrue);
    });
  });

  group('migration file', () {
    final sql = _read('supabase/pack2_security_hardening.sql');
    test('drops the direct-insert policies and the no-PIN group checkout', () {
      for (final p in [
        '"orders: insert own"',
        '"order_items: insert own"',
        '"errand_requests: insert own"',
        '"profiles: insert own row"',
      ]) {
        expect(sql.contains('drop policy if exists $p'), isTrue, reason: p);
      }
      expect(
          sql.contains('drop function if exists public.checkout_group_order('
              'uuid, jsonb, numeric, text, text);'),
          isTrue);
    });
    test('has no begin/commit (so tests can wrap it) and a rollback file', () {
      expect(RegExp(r'^\s*(begin|commit);', multiLine: true).hasMatch(sql),
          isFalse);
      expect(File('supabase/pack2_security_hardening_ROLLBACK.sql').existsSync(),
          isTrue);
    });
  });
}
