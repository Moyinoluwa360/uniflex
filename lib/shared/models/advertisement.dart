/// What tapping an advertisement card does.
enum AdLinkType {
  none,
  vendor,
  wallet,
  url;

  static AdLinkType fromName(String? raw) => switch (raw) {
        'vendor' => AdLinkType.vendor,
        'wallet' => AdLinkType.wallet,
        'url' => AdLinkType.url,
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
