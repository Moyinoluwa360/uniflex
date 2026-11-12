// Pack 1 / Part 4 — wallet funding guards that can be checked without
// Paystack. The money rules themselves are proven in
// supabase/pack1_wallet_funding_fixes_test.sql (12 checks, rolled back).
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/config/env_config.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('"test mode" wording only with a pk_test_ key', () {
    dotenv.testLoad(fileInput: 'PAYSTACK_PUBLIC_KEY=pk_test_abc');
    expect(EnvConfig.isPaystackTestMode, isTrue);
    dotenv.testLoad(fileInput: 'PAYSTACK_PUBLIC_KEY=pk_live_abc');
    expect(EnvConfig.isPaystackTestMode, isFalse);
    dotenv.testLoad(fileInput: '');
    expect(EnvConfig.isPaystackTestMode, isFalse);
  });

  test('webhook: signature checked on the raw body BEFORE parsing', () {
    final src = _read('supabase/functions/paystack-webhook/index.ts');
    final raw = src.indexOf('await req.text()');
    final check = src.indexOf('timingSafeEqual(presented, expected)');
    final parse = src.indexOf('JSON.parse(rawBody)');
    expect(raw, greaterThan(0));
    expect(check, greaterThan(raw));
    expect(parse, greaterThan(check));
    expect(src.contains('SHA-512'), isTrue);
  });

  test('webhook: email fallback is an exact (escaped) match, never a pattern',
      () {
    final src = _read('supabase/functions/paystack-webhook/index.ts');
    expect(src.contains('.ilike("email", payerEmail)'), isFalse);
    expect(src.contains('.ilike("email", exact)'), isTrue);
    expect(src.contains('profiles?.length === 1'), isTrue);
  });

  test('virtual account: bank follows the key mode (no hard-coded test bank)',
      () {
    final src = _read('supabase/functions/create-virtual-account/index.ts');
    expect(src.contains('preferred_bank: "test-bank"'), isFalse);
    expect(src.contains('preferred_bank: bank.slug'), isTrue);
    expect(src.contains('startsWith("sk_test_")'), isTrue);
  });

  test('SQL fix closes direct calls to the money functions', () {
    final sql = _read('supabase/pack1_wallet_funding_fixes.sql');
    expect(
        sql.contains(
            'revoke all on function public.credit_wallet(uuid, numeric, text) from public, anon, authenticated'),
        isTrue);
    expect(
        sql.contains(
            'revoke all on function public._refund_order(uuid) from public, anon, authenticated'),
        isTrue);
  });

  test('the app never calls credit_wallet or _refund_order itself', () {
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final s = f.readAsStringSync();
      expect(s.contains("'credit_wallet'"), isFalse, reason: f.path);
      expect(s.contains("'_refund_order'"), isFalse, reason: f.path);
    }
  });
}
