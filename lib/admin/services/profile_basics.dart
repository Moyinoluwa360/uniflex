import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/services/supabase/supabase_providers.dart';

/// The few profile fields Admin screens need to show who someone is.
///
/// Why this exists (Pack 4C): the `profiles` table only lets a user read
/// their OWN row, so every Admin screen that read it for a student or rider
/// quietly got nothing back — blank names in the support inbox, no rider on
/// order cards, "Unknown" in analytics. Admin now reads names through the
/// `admin_profile_basics` function, which is admin-only and returns just
/// these five fields.
class ProfileBasics {
  const ProfileBasics({
    required this.id,
    this.role,
    this.nickname,
    this.fullName,
    this.phone,
    this.email,
  });

  final String id;
  final String? role;
  final String? nickname;
  final String? fullName;
  final String? phone;
  final String? email;

  factory ProfileBasics.fromRow(Map<String, dynamic> row) => ProfileBasics(
        id: row['id'] as String,
        role: row['role'] as String?,
        nickname: row['nickname'] as String?,
        fullName: row['full_name'] as String?,
        phone: row['phone'] as String?,
        email: row['email'] as String?,
      );

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// The main name: nickname, else full name, else [fallback].
  String displayName([String fallback = 'Unknown']) =>
      _clean(nickname) ?? _clean(fullName) ?? fallback;

  /// The line shown underneath: the full name — only when there is a
  /// nickname above it to differ from.
  String? get secondaryName {
    final nick = _clean(nickname);
    final full = _clean(fullName);
    if (nick == null || full == null) return null;
    if (nick.toLowerCase() == full.toLowerCase()) return null;
    return full;
  }

  /// True when [query] (already lower-cased) is found in the nickname,
  /// full name or phone.
  bool matches(String query) {
    if (query.isEmpty) return true;
    return (nickname ?? '').toLowerCase().contains(query) ||
        (fullName ?? '').toLowerCase().contains(query) ||
        (phone ?? '').toLowerCase().contains(query);
  }
}

/// Builds the stable family key for [adminProfileBasicsProvider]: unique,
/// non-empty ids, sorted, comma-joined (so the same set never refetches).
String profileIdsKey(Iterable<String?> ids) {
  final set = <String>{
    for (final id in ids)
      if (id != null && id.trim().isNotEmpty) id.trim(),
  };
  final list = set.toList()..sort();
  return list.join(',');
}

/// Names for a set of profile ids (see [profileIdsKey]). Failing to load
/// names must never break a screen, so errors give an empty map.
final adminProfileBasicsProvider = FutureProvider.autoDispose
    .family<Map<String, ProfileBasics>, String>((ref, idsKey) async {
  if (idsKey.isEmpty) return const {};
  final ids = idsKey.split(',');
  try {
    final rows = await ref
        .watch(supabaseClientProvider)
        .rpc('admin_profile_basics', params: {'p_ids': ids});
    return {
      for (final r in (rows as List))
        (r as Map)['id'] as String:
            ProfileBasics.fromRow(Map<String, dynamic>.from(r)),
    };
  } catch (_) {
    return const {};
  }
});
