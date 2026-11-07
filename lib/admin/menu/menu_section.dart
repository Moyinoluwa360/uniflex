import '../../shared/models/product.dart';

/// The four sections of a vendor menu, in the order students see them.
///
/// The student vendor page groups by `products.section` (+ `food_subsection`
/// for food); Admin now groups by exactly the same two fields, so an item can
/// never sit in one section for Admin and another for students. (Before Pack
/// 4C Admin grouped by the old free-text `category`, which is how items could
/// land under the wrong heading.)
enum MenuSection {
  meals('Meals', 'food', 'meal'),
  proteins('Proteins / Toppings', 'food', 'protein_topping'),
  drinks('Drinks', 'drinks', null),
  others('Others', 'others', null);

  const MenuSection(this.label, this.section, this.foodSubsection);

  /// Heading shown to Admin.
  final String label;

  /// Value stored in `products.section`: food | drinks | others.
  final String section;

  /// Value stored in `products.food_subsection` (food only).
  final String? foodSubsection;

  /// Food items occupy a pack; drinks and others do not.
  bool get requiresPack => section == 'food';

  /// Which section a product belongs to — same rule the student page uses.
  static MenuSection of(Product p) => switch (p.section) {
        'food' => p.foodSubsection == 'protein_topping' ? proteins : meals,
        'drinks' => drinks,
        _ => others,
      };
}
