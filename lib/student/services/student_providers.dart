import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/models/achievement.dart';
import '../../shared/models/advertisement.dart';
import '../../shared/services/supabase/supabase_providers.dart';
import 'student_service.dart';

final studentServiceProvider = Provider<StudentService>((ref) {
  return StudentService(ref.watch(supabaseClientProvider));
});

/// Loyalty stats: total_orders, reward_points, membership_tier, etc.
final studentStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.watch(studentServiceProvider).getStudentStats();
});

/// Badges earned by the current student.
final userAchievementsProvider = FutureProvider<List<Achievement>>((ref) async {
  return ref.watch(studentServiceProvider).getUserAchievements();
});

/// Live member list for a group order session.
final groupMembersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, groupId) {
  return ref.watch(studentServiceProvider).streamGroupMembers(groupId);
});

/// Phase 10: live home-page advertisement banners, admin-managed.
final liveAdvertisementsProvider =
    FutureProvider<List<Advertisement>>((ref) async {
  return ref.watch(studentServiceProvider).getLiveAdvertisements();
});
