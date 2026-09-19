import '../services/auth/user_role.dart';

/// A row from the `profiles` table — see `supabase/schema.sql`. Covers all
/// three roles; the student-only fields are null for Rider/Admin rows.
class Profile {
  const Profile({
    required this.id,
    required this.role,
    required this.onboardingComplete,
    this.email,
    this.phone,
    this.phoneVerifiedAt,
    this.nickname,
    this.fullName,
    this.matricNumber,
    this.school,
    this.dateOfBirth,
    this.referralCode,
    this.referredByCode,
    this.adminTier,
    this.rewardPoints = 0,
    this.membershipTier = 'Bronze',
    this.lifetimeSpending = 0,
    this.totalOrders = 0,
    this.referralCount = 0,
    this.fcmToken,
    this.isActive = true,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      role: UserRole.values.byName(map['role'] as String),
      onboardingComplete: map['onboarding_complete'] as bool? ?? false,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      phoneVerifiedAt: map['phone_verified_at'] == null
          ? null
          : DateTime.parse(map['phone_verified_at'] as String),
      nickname: map['nickname'] as String?,
      fullName: map['full_name'] as String?,
      matricNumber: map['matric_number'] as String?,
      school: map['school'] as String?,
      dateOfBirth: map['date_of_birth'] == null
          ? null
          : DateTime.parse(map['date_of_birth'] as String),
      referralCode: map['referral_code'] as String?,
      referredByCode: map['referred_by_code'] as String?,
      adminTier: map['admin_tier'] as String?,
      rewardPoints: map['reward_points'] as int? ?? 0,
      membershipTier: map['membership_tier'] as String? ?? 'Bronze',
      lifetimeSpending: (map['lifetime_spending'] as num?)?.toDouble() ?? 0,
      totalOrders: map['total_orders'] as int? ?? 0,
      referralCount: map['referral_count'] as int? ?? 0,
      fcmToken: map['fcm_token'] as String?,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final UserRole role;
  final bool onboardingComplete;
  final String? email;
  final String? phone;
  final DateTime? phoneVerifiedAt;
  final String? nickname;
  final String? fullName;
  final String? matricNumber;
  final String? school;
  final DateTime? dateOfBirth;
  final String? referralCode;
  final String? referredByCode;

  /// Only set for admin accounts. `null` or `'super_admin'` → full access;
  /// `'kitchen_staff'` → kitchen queue only. See Phase 4 schema comments.
  final String? adminTier;

  // Phase 6 loyalty fields
  final int rewardPoints;
  final String membershipTier; // 'Bronze' | 'Silver' | 'Gold' | 'Platinum'
  final double lifetimeSpending;
  final int totalOrders;
  final int referralCount;
  final String? fcmToken;

  /// Post-testing fixes, Section 7: false once Admin has removed/
  /// deactivated this account (currently only exposed for riders). The
  /// account and its history are never deleted — only sign-in is blocked.
  final bool isActive;

  /// True when this admin account is restricted to the kitchen queue only.
  bool get isKitchenStaff => role == UserRole.admin && adminTier == 'kitchen_staff';

  /// Points needed to reach the next tier.
  double get spendingToNextTier {
    if (lifetimeSpending >= 50000) return 0;
    if (lifetimeSpending >= 20000) return 50000 - lifetimeSpending;
    if (lifetimeSpending >= 5000) return 20000 - lifetimeSpending;
    return 5000 - lifetimeSpending;
  }

  /// 0.0–1.0 progress toward the next tier.
  double get tierProgress {
    if (lifetimeSpending >= 50000) return 1.0;
    if (lifetimeSpending >= 20000) return (lifetimeSpending - 20000) / 30000;
    if (lifetimeSpending >= 5000) return (lifetimeSpending - 5000) / 15000;
    return lifetimeSpending / 5000;
  }
}
