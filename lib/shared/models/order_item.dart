import 'cart_item.dart' show SelectedOption;

/// A line item inside a placed order, stored in `order_items`.
/// [selectedOptions] is decoded from the `selected_options` jsonb column.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    this.productId,
    this.selectedOptions = const [],
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    final rawOptions =
        (map['selected_options'] as List<dynamic>?) ?? <dynamic>[];
    return OrderItem(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      productName: map['product_name'] as String,
      quantity: map['quantity'] as int,
      unitPrice: (map['unit_price'] as num).toDouble(),
      productId: map['product_id'] as String?,
      selectedOptions: rawOptions
          .cast<Map<String, dynamic>>()
          .map(SelectedOption.fromJson)
          .toList(),
    );
  }

  final String id;
  final String orderId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final String? productId;
  final List<SelectedOption> selectedOptions;

  double get lineTotal => unitPrice * quantity;

  String get optionsSummary {
    if (selectedOptions.isEmpty) return '';
    return selectedOptions.map((o) => o.name).join(', ');
  }
}
