/// What is inside an order — the ONE structure every role reads (Pack 4B).
///
/// Comes from the server function `get_order_breakdown(order_id)` and
/// nowhere else. Never contains delivery / commitment / service fees.
library;

class BreakdownLine {
  const BreakdownLine({
    required this.name,
    required this.quantity,
    this.unitPrice,
    this.lineTotal,
  });

  factory BreakdownLine.fromJson(Map<String, dynamic> m) => BreakdownLine(
        name: m['name'] as String? ?? 'Item',
        quantity: (m['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (m['unit_price'] as num?)?.toDouble(),
        lineTotal: (m['line_total'] as num?)?.toDouble(),
      );

  final String name;
  final int quantity;

  /// Absent for the contents of a pack (the pack carries one price).
  final double? unitPrice;
  final double? lineTotal;
}

class BreakdownPack {
  const BreakdownPack({
    required this.index,
    required this.price,
    required this.items,
  });

  factory BreakdownPack.fromJson(Map<String, dynamic> m) => BreakdownPack(
        index: (m['index'] as num?)?.toInt() ?? 1,
        price: (m['price'] as num?)?.toDouble() ?? 0,
        items: _lines(m['items']),
      );

  /// 1-based pack number.
  final int index;
  final double price;
  final List<BreakdownLine> items;

  /// "Pack 1 · ₦200"
  String get title => 'Pack $index · ₦${price.toStringAsFixed(0)}';

  /// "Pack 1" — what a gift recipient sees (no price anywhere).
  String get titleNoPrice => 'Pack $index';
}

class VendorBreakdown {
  const VendorBreakdown({
    required this.vendorId,
    required this.vendorName,
    this.vendorLocation,
    this.packs = const [],
    this.items = const [],
    this.drinks = const [],
    this.others = const [],
    this.itemCount = 0,
    this.itemsTotal = 0,
    this.packsTotal = 0,
    this.vendorTotal = 0,
  });

  factory VendorBreakdown.fromJson(Map<String, dynamic> m) => VendorBreakdown(
        vendorId: m['vendor_id'] as String? ?? '',
        vendorName: m['vendor_name'] as String? ?? 'Vendor',
        vendorLocation: m['vendor_location'] as String?,
        packs: ((m['packs'] as List?) ?? const [])
            .map((p) =>
                BreakdownPack.fromJson(Map<String, dynamic>.from(p as Map)))
            .toList(),
        items: _lines(m['items']),
        drinks: _lines(m['drinks']),
        others: _lines(m['others']),
        itemCount: (m['item_count'] as num?)?.toInt() ?? 0,
        itemsTotal: (m['items_total'] as num?)?.toDouble() ?? 0,
        packsTotal: (m['packs_total'] as num?)?.toDouble() ?? 0,
        vendorTotal: (m['vendor_total'] as num?)?.toDouble() ?? 0,
      );

  final String vendorId;
  final String vendorName;
  final String? vendorLocation;
  final List<BreakdownPack> packs;

  /// Food that is not inside any pack (plain list; usually empty).
  final List<BreakdownLine> items;
  final List<BreakdownLine> drinks;
  final List<BreakdownLine> others;
  final int itemCount;
  final double itemsTotal;
  final double packsTotal;
  final double vendorTotal;

  bool get hasPacks => packs.isNotEmpty;
  bool get isEmpty =>
      packs.isEmpty && items.isEmpty && drinks.isEmpty && others.isEmpty;
}

class OrderBreakdownData {
  const OrderBreakdownData({
    required this.orderId,
    required this.kind,
    required this.vendors,
  });

  factory OrderBreakdownData.fromJson(Map<String, dynamic> m) =>
      OrderBreakdownData(
        orderId: m['order_id'] as String? ?? '',
        kind: m['kind'] as String? ?? 'delivery',
        vendors: ((m['vendors'] as List?) ?? const [])
            .where((v) => v != null)
            .map((v) =>
                VendorBreakdown.fromJson(Map<String, dynamic>.from(v as Map)))
            .toList(),
      );

  final String orderId;

  /// 'delivery' | 'pickup' | 'order'
  final String kind;
  final List<VendorBreakdown> vendors;

  bool get isMultiVendor => vendors.length > 1;
}

List<BreakdownLine> _lines(Object? raw) => ((raw as List?) ?? const [])
    .map((l) => BreakdownLine.fromJson(Map<String, dynamic>.from(l as Map)))
    .toList();
