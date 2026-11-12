/// A menu item from the `products` table.
///
/// Round 7 adds structured [section] and [foodSubsection] fields replacing
/// the free-text [category] for display grouping. The legacy [category]
/// column is kept for backward compatibility but is no longer the primary
/// grouping mechanism.
class Product {
  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.description,
    required this.category,
    required this.basePrice,
    this.imageUrl,
    this.isAvailable = true,
    this.requiresPack = false,
    this.section = 'food',
    this.foodSubsection,
  });

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'] as String,
      vendorId: map['vendor_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String? ?? '',
      category: map['category'] as String,
      basePrice: (map['base_price'] as num).toDouble(),
      imageUrl: map['image_url'] as String?,
      isAvailable: map['is_available'] as bool? ?? true,
      requiresPack: map['requires_pack'] as bool? ?? false,
      section: map['section'] as String? ?? 'food',
      foodSubsection: map['food_subsection'] as String?,
    );
  }

  final String id;
  final String vendorId;
  final String name;
  final String description;

  /// Legacy free-text category. Kept for backward compat but [section]
  /// and [foodSubsection] are the canonical grouping fields.
  final String category;
  final double basePrice;
  final String? imageUrl;
  final bool isAvailable;

  /// True when this item needs to be packaged into a container.
  final bool requiresPack;

  /// Round 7: top-level menu section — 'food' | 'drinks' | 'others'.
  final String section;

  /// Round 7: only meaningful when [section] == 'food'.
  /// 'meal' (counts toward pack capacity) or 'protein_topping' (unlimited).
  final String? foodSubsection;

  /// True when this is a meal item that counts toward the pack's 8-spoon
  /// capacity limit.
  bool get isMeal => section == 'food' && foodSubsection == 'meal';

  /// True when this is a protein/topping (inside a pack but no capacity limit).
  bool get isProteinTopping =>
      section == 'food' && foodSubsection == 'protein_topping';

  /// Display label for the section.
  String get sectionLabel => switch (section) {
        'food' => 'Food',
        'drinks' => 'Drinks',
        'others' => 'Others',
        _ => 'Others',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'vendor_id': vendorId,
        'name': name,
        'description': description,
        'category': category,
        'base_price': basePrice,
        'image_url': imageUrl,
        'is_available': isAvailable,
        'requires_pack': requiresPack,
        'section': section,
        'food_subsection': foodSubsection,
      };
}

/// Products grouped by their (trimmed) category, categories A→Z, items in the
/// order given. An empty category is shown as "Menu". Shared by the admin
/// manager and the student vendor page so both group identically.
Map<String, List<Product>> groupByCategory(List<Product> products) {
  final out = <String, List<Product>>{};
  for (final p in products) {
    final key = p.category.trim().isEmpty ? 'Menu' : p.category.trim();
    (out[key] ??= []).add(p);
  }
  final keys = out.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return {for (final k in keys) k: out[k]!};
}
