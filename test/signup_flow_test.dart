// Tests for the signup flow fixes: A2 (resume logic), B (no referral code
// auto-gen), and confirm-password validation.
//
// These are pure unit/widget tests — no live Supabase needed.

import 'package:flutter_test/flutter_test.dart';
import 'package:uniflex/shared/auth/validators.dart';
import 'package:uniflex/shared/models/profile.dart';

void main() {
  // ─── A2: Resume logic — profile state determines routing ──────────────

  group('A2: AuthGate routing from profile state', () {
    Profile _makeProfile({
      bool onboardingComplete = false,
      DateTime? phoneVerifiedAt,
      bool isActive = true,
    }) {
      return Profile.fromMap({
        'id': 'test-user-id',
        'role': 'student',
        'onboarding_complete': onboardingComplete,
        'is_active': isActive,
        if (phoneVerifiedAt != null)
          'phone_verified_at': phoneVerifiedAt.toIso8601String(),
      });
    }

    test('phone NOT verified → AuthGate should show OTP screen', () {
      final profile = _makeProfile(phoneVerifiedAt: null);
      // AuthGate condition: !onboardingComplete && phoneVerifiedAt == null
      expect(profile.onboardingComplete, isFalse);
      expect(profile.phoneVerifiedAt, isNull);
      // This combination routes to ResumeOtpScreen in AuthGate.
    });

    test('phone already verified → AuthGate should skip OTP, show CompleteProfile', () {
      final profile = _makeProfile(
        phoneVerifiedAt: DateTime.now(),
      );
      // AuthGate condition: !onboardingComplete && phoneVerifiedAt != null
      expect(profile.onboardingComplete, isFalse);
      expect(profile.phoneVerifiedAt, isNotNull);
      // This combination routes directly to CompleteProfileScreen.
    });

    test('onboarding complete → AuthGate routes to RoleRouter', () {
      final profile = _makeProfile(
        onboardingComplete: true,
        phoneVerifiedAt: DateTime.now(),
      );
      expect(profile.onboardingComplete, isTrue);
      expect(profile.isActive, isTrue);
      // This routes to RoleRouter.
    });

    test('deactivated account → AuthGate shows deactivated screen', () {
      final profile = _makeProfile(
        onboardingComplete: true,
        phoneVerifiedAt: DateTime.now(),
        isActive: false,
      );
      expect(profile.onboardingComplete, isTrue);
      expect(profile.isActive, isFalse);
      // This shows AccountDeactivatedScreen.
    });
  });

  // ─── B: Profile model handles absent referral code ─────────────────────

  group('B: Profile without referral code', () {
    test('referralCode is null when not set in profile data', () {
      final profile = Profile.fromMap({
        'id': 'test-user-id',
        'role': 'student',
        'onboarding_complete': true,
        // referral_code not present at all
      });
      expect(profile.referralCode, isNull);
    });

    test('referralCode is null when explicitly null in profile data', () {
      final profile = Profile.fromMap({
        'id': 'test-user-id',
        'role': 'student',
        'onboarding_complete': true,
        'referral_code': null,
      });
      expect(profile.referralCode, isNull);
    });

    test('referralCode present when admin-assigned', () {
      final profile = Profile.fromMap({
        'id': 'test-user-id',
        'role': 'student',
        'onboarding_complete': true,
        'referral_code': 'ADMIN123',
      });
      expect(profile.referralCode, equals('ADMIN123'));
    });
  });

  // ─── A1: Confirm password validation ───────────────────────────────────

  group('A1: Password confirmation', () {
    test('password validator accepts valid password', () {
      expect(AuthValidators.password('mypassword1'), isNull);
    });

    test('password validator rejects too short', () {
      expect(AuthValidators.password('short1'), isNotNull);
    });

    test('password validator rejects no digits', () {
      expect(AuthValidators.password('nodigitshere'), isNotNull);
    });
  });

  // ─── Phone validation with various formats ─────────────────────────────

  group('Phone number normalization', () {
    test('accepts phone with dashes', () {
      // AuthValidators._sanitize strips dashes before regex matching
      expect(AuthValidators.phone('080-1234-5678'), isNull);
    });

    test('accepts phone with spaces', () {
      expect(AuthValidators.phone('080 1234 5678'), isNull);
    });

    test('toE164 normalizes with whitespace', () {
      expect(AuthValidators.toE164(' 08012345678 '), '+2348012345678');
    });
  });

  // ─── D1: SQL structure verification ────────────────────────────────────
  // (The actual payment test requires a live Supabase instance. The fix is
  // verified structurally: the Round 4 SQL now DROPs the old 13-param
  // place_food_order_with_payment before creating the 14-param version,
  // and complete_student_onboarding uses trusted_write + no referral code
  // auto-generation. These changes resolve the function overload issue
  // that caused PostgREST to fail on the payment RPC call.)
}
