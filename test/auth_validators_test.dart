// Pure unit tests for the Step One / Step Two field rules — no widgets,
// no Supabase, so these run instantly and can't flake on I/O.

import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/auth/validators.dart';

void main() {
  group('AuthValidators.password', () {
    test('rejects fewer than 8 characters', () {
      expect(AuthValidators.password('abc123'), isNotNull);
    });

    test('rejects 8+ characters with no digit', () {
      expect(AuthValidators.password('abcdefgh'), isNotNull);
    });

    test('accepts 8+ characters with at least one digit', () {
      expect(AuthValidators.password('abcdefg1'), isNull);
    });
  });

  group('AuthValidators.email', () {
    test('rejects missing @', () {
      expect(AuthValidators.email('not-an-email'), isNotNull);
    });

    test('accepts a well-formed address', () {
      expect(AuthValidators.email('student@run.edu.ng'), isNull);
    });
  });

  group('AuthValidators.phone', () {
    test('accepts local 11-digit Nigerian numbers', () {
      expect(AuthValidators.phone('08012345678'), isNull);
    });

    test('accepts already-E.164 numbers', () {
      expect(AuthValidators.phone('+2348012345678'), isNull);
    });

    test('rejects too-short numbers', () {
      expect(AuthValidators.phone('080123'), isNotNull);
    });
  });

  group('AuthValidators.toE164', () {
    test('converts a local number to +234 form', () {
      expect(AuthValidators.toE164('08012345678'), '+2348012345678');
    });

    test('leaves an already-E.164 number unchanged', () {
      expect(AuthValidators.toE164('+2348012345678'), '+2348012345678');
    });
  });
}
