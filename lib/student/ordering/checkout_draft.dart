import '../../shared/models/delivery_location.dart';
import '../gifts/gift_models.dart';
import 'cart_provider.dart';

/// Pack-bracket calculation: how many brackets a vendor's packs fill.
/// 0 packs (drinks/others only) → 1×, 1–3 → 1×, 4–6 → 2×, 7–9 → 3×, etc.
int packBrackets(int foodPacks) => foodPacks <= 0 ? 1 : ((foodPacks + 2) ~/ 3);

/// Delivery fee for one vendor given the location price and pack count.
/// DISPLAY ONLY — the server recomputes every amount and is the authority.
double vendorDeliveryFee(double locationPrice, int foodPacks) =>
    locationPrice * packBrackets(foodPacks);

/// One cart line, as the payment page shows it and as the RPC receives it
/// (the RPC only ever reads [productId] and [quantity]).
class DraftItem {
  const DraftItem({
    required this.productId,
    required this.name,
    required this.quantity,
    required this.lineTotal,
  });

  final String productId;
  final String name;
  final int quantity;

  /// For display only; never sent to the server.
  final double lineTotal;
}

/// One vendor's part of the checkout.
class DraftVendor {
  const DraftVendor({
    required this.vendorId,
    required this.vendorName,
    required this.isUniflex,
    required this.items,
    required this.packs,
    required this.packFee,
    this.orderingStyle = 'pack_based',
  });

  final String vendorId;
  final String vendorName;
  final bool isUniflex;
  final List<DraftItem> items;

  /// Pack allocation: one map per pack, `productId → quantity`.
  final List<Map<String, int>> packs;

  /// Display only (packs × vendor pack price). Never sent.
  final double packFee;

  /// The vendor's style when this cart was built (`pack_based` /
  /// `fixed_menu`). Sent so the server can refuse a cart built for the
  /// other style after an admin switched it (VENDOR_STYLE_CHANGED).
  final String orderingStyle;

  int get packCount => packs.length;
  double get foodAmount =>
      items.fold(0.0, (sum, i) => sum + i.lineTotal) + packFee;
}

/// Everything the student chose at checkout, held IN MEMORY between the
/// checkout form and the payment page. Nothing exists in the database
/// until the student pays; creating this object touches no provider and
/// does not change the cart.
class CheckoutDraft {
  const CheckoutDraft({
    required this.isPickup,
    required this.vendors,
    this.location,
    this.locationDetails,
    this.note,
    this.scheduledFor,
    this.giftRecipient,
    this.giftMessage,
  });

  /// Snapshot of the current cart plus the chosen options.
  factory CheckoutDraft.fromCart(
    CartState cart, {
    required bool isPickup,
    DeliveryLocation? location,
    String? locationDetails,
    String? note,
    DateTime? scheduledFor,
    GiftRecipient? giftRecipient,
    String? giftMessage,
  }) {
    final vendors = <DraftVendor>[];
    for (final g in cart.groups.values) {
      if (g.isEmpty) continue;
      vendors.add(DraftVendor(
        vendorId: g.vendor.id,
        vendorName: g.vendor.name,
        isUniflex: g.vendor.isUniflex,
        items: [
          for (final i in g.items)
            DraftItem(
              productId: i.product.id,
              name: i.product.name,
              quantity: i.quantity,
              lineTotal: i.lineTotal,
            ),
        ],
        packs: [
          for (final p in g.packContents)
            {
              for (final e in p.entries)
                if (e.value > 0) e.key: e.value,
            },
        ],
        packFee: g.packFee,
        orderingStyle: g.vendor.orderingStyle.value,
      ));
    }
    final trimmedDetails = locationDetails?.trim();
    final trimmedNote = note?.trim();
    return CheckoutDraft(
      isPickup: isPickup,
      vendors: vendors,
      location: location,
      locationDetails: (trimmedDetails == null || trimmedDetails.isEmpty)
          ? null
          : trimmedDetails,
      note: (trimmedNote == null || trimmedNote.isEmpty) ? null : trimmedNote,
      scheduledFor: scheduledFor,
      // A gift is only ever a food DELIVERY.
      giftRecipient: isPickup ? null : giftRecipient,
      giftMessage: (isPickup || giftRecipient == null)
          ? null
          : ((giftMessage?.trim().isEmpty ?? true)
              ? null
              : giftMessage!.trim()),
    );
  }

  final bool isPickup;
  final List<DraftVendor> vendors;
  final DeliveryLocation? location;
  final String? locationDetails;
  final String? note;
  final DateTime? scheduledFor;

  /// Set when the student chose "Send as a gift" (food delivery only).
  final GiftRecipient? giftRecipient;
  final String? giftMessage;
  bool get isGift => giftRecipient != null && !isPickup;

  double get foodAmount => vendors.fold(0.0, (sum, v) => sum + v.foodAmount);
}

/// One line on the payment page.
class QuoteLine {
  const QuoteLine(this.label, this.amount);
  final String label;
  final double amount;
}

/// What the payment page shows. A preview: the server recomputes it all.
class CheckoutQuote {
  const CheckoutQuote({
    required this.lines,
    required this.serviceCharge,
    required this.total,
  });

  /// Per-vendor delivery fees (delivery) — empty for pickup.
  final List<QuoteLine> lines;

  /// Charged once per order; 0 for pickup.
  final double serviceCharge;
  final double total;
}

/// Delivery: each vendor's delivery fee as its own line, then the service
/// charge once. Pickup: the full food amount, no fees.
CheckoutQuote quoteFor(CheckoutDraft draft, double serviceCharge) {
  if (draft.isPickup) {
    final food = draft.foodAmount;
    return CheckoutQuote(
      lines: [
        QuoteLine(
            draft.vendors.every((v) => v.orderingStyle == 'fixed_menu')
                ? 'Food'
                : 'Food + packs',
            food)
      ],
      serviceCharge: 0,
      total: food,
    );
  }
  final price = draft.location?.price ?? 0;
  final lines = <QuoteLine>[
    for (final v in draft.vendors)
      QuoteLine('Delivery fee · ${v.vendorName}',
          vendorDeliveryFee(price, v.packCount)),
  ];
  final fees = lines.fold(0.0, (sum, l) => sum + l.amount);
  return CheckoutQuote(
    lines: lines,
    serviceCharge: serviceCharge,
    total: fees + serviceCharge,
  );
}
