import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/achievement.dart';
import '../../shared/models/gift.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import 'student_service.dart';

final studentServiceProvider = Provider<StudentService>((ref) {
  return StudentService(ref.watch(supabaseClientProvider));
});

/// Loyalty stats: total_orders, reward_points, membership_tier, etc.
final studentStatsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(studentServiceProvider).getStudentStats();
});

/// Top-10 referral leaderboard.
final referralLeaderboardProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(studentServiceProvider).getReferralLeaderboard();
});

/// Badges earned by the current student.
final userAchievementsProvider =
    FutureProvider<List<Achievement>>((ref) async {
  return ref.watch(studentServiceProvider).getUserAchievements();
});

/// Sent + received gifts for the current student.
final giftsProvider = FutureProvider<List<Gift>>((ref) async {
  return ref.watch(studentServiceProvider).getGifts();
});

/// Live member list for a group order session.
final groupMembersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>(
        (ref, groupId) {
  return ref.watch(studentServiceProvider).streamGroupMembers(groupId);
});
