import 'package:flutter/material.dart';

/// An Around service category, admin-configurable via the `Manage` hub
/// (post-testing fixes, Section 9) — replaces the old hardcoded
/// `AroundCategory` enum. Students only ever see active rows; Admin can
/// see and edit inactive ones too.
class AroundCategoryData {
  const AroundCategoryData({
    required this.id,
    required this.key,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.iconName,
    required this.flatFee,
    required this.isActive,
    required this.sortOrder,
  });

  factory AroundCategoryData.fromMap(Map<String, dynamic> map) {
    return AroundCategoryData(
      id: map['id'] as String,
      key: map['key'] as String,
      title: map['title'] as String,
      subtitle: map['subtitle'] as String? ?? '',
      description: map['description'] as String? ?? '',
      iconName: map['icon_name'] as String? ?? 'explore',
      flatFee: (map['flat_fee'] as num).toDouble(),
      isActive: map['is_active'] as bool? ?? true,
      sortOrder: map['sort_order'] as int? ?? 0,
    );
  }

  final String id;
  final String key;
  final String title;
  final String subtitle;
  final String description;
  final String iconName;
  final double flatFee;
  final bool isActive;
  final int sortOrder;

  static const _iconsByName = {
    'assignment': Icons.assignment_outlined,
    'laundry': Icons.local_laundry_service_outlined,
    'home': Icons.home_outlined,
    'storefront': Icons.storefront_outlined,
    'send': Icons.send_outlined,
    'explore': Icons.explore_outlined,
    'shopping_bag': Icons.shopping_bag_outlined,
    'directions_walk': Icons.directions_walk_outlined,
    'local_shipping': Icons.local_shipping_outlined,
    'print': Icons.print_outlined,
  };

  IconData get icon => iconFor(iconName);

  static IconData iconFor(String name) =>
      _iconsByName[name] ?? Icons.explore_outlined;

  /// Every icon name selectable in the admin category form — keeps the
  /// dropdown and the render-time lookup above in one place.
  static List<String> get availableIconNames => _iconsByName.keys.toList();
}
