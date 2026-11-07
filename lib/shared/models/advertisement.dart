import '../utils/ad_link.dart';

/// Kept for the database column (`link_type`: none | url). Since Pack 4C an
/// ad's link is simply "present or not" — see [Advertisement.webLink].
enum AdLinkType {
  none,
  vendor,
  wallet,
  url;

  static AdLinkType fromName(String? raw) => switch (raw) {
        'url' => AdLinkType.url,
        // vendor and wallet were removed in Fix Pack 3; map to none so old
        // DB rows (pre-migration) are still readable without a crash.
        _ => AdLinkType.none,
      };
}

/// A banner in the student home carousel, managed by Admin.
class Advertisement {
  const Advertisement({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.isDark,
    required this.isActive,
    required this.sortOrder,
    this.imageUrl,
    this.linkType = AdLinkType.none,
    this.linkValue,
    this.startsAt,
    this.endsAt,
  });

  factory Advertisement.fromMap(Map<String, dynamic> map) {
    return Advertisement(
      id: map['id'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String? ?? '',
      isDark: map['is_dark'] as bool? ?? false,
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      imageUrl: map['image_url'] as String?,
      linkType: AdLinkType.fromName(map['link_type'] as String?),
      linkValue: map['link_value'] as String?,
      startsAt: map['starts_at'] == null
          ? null
          : DateTime.parse(map['starts_at'] as String).toLocal(),
      endsAt: map['ends_at'] == null
          ? null
          : DateTime.parse(map['ends_at'] as String).toLocal(),
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final bool isDark;
  final bool isActive;
  final int sortOrder;
  final String? imageUrl;
  final AdLinkType linkType;
  final String? linkValue;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// The ad's usable web link (http/https), or null. A missing, empty or
  /// malformed link — or an old vendor/wallet target — is simply "no link";
  /// it can never throw.
  String? get webLink =>
      linkType == AdLinkType.url ? normalizeAdLink(linkValue) : null;

  /// True when the popup should offer a "Visit" button.
  bool get hasLink => webLink != null;

  /// True when this ad should be on screen right now. The read policy
  /// already filters these out for students, but admin reads every row, so
  /// the management screen needs to tell live from scheduled/expired.
  bool get isLive {
    if (!isActive) return false;
    final now = DateTime.now();
    if (startsAt != null && startsAt!.isAfter(now)) return false;
    if (endsAt != null && !endsAt!.isAfter(now)) return false;
    return true;
  }

  /// Short human label for the admin list: why an ad is not showing.
  String get statusLabel {
    if (!isActive) return 'Paused';
    final now = DateTime.now();
    if (startsAt != null && startsAt!.isAfter(now)) return 'Scheduled';
    if (endsAt != null && !endsAt!.isAfter(now)) return 'Ended';
    return 'Live';
  }
}
