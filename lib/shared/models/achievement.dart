/// A badge from the `achievements` catalogue, optionally with an
/// `earnedAt` timestamp when returned via `get_user_achievements`.
class Achievement {
  const Achievement({
    required this.code,
    required this.name,
    required this.description,
    required this.iconName,
    this.earnedAt,
  });

  factory Achievement.fromMap(Map<String, dynamic> map) {
    return Achievement(
      code: map['code'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      iconName: map['icon_name'] as String,
      earnedAt: map['earned_at'] == null
          ? null
          : DateTime.parse(map['earned_at'] as String),
    );
  }

  final String code;
  final String name;
  final String description;

  /// Material icon name string (used with `IconData` lookup in UI).
  final String iconName;
  final DateTime? earnedAt;

  bool get isEarned => earnedAt != null;
}
