import '../../shared/models/delivery_group.dart' show DeliveryGroupStatus;
import '../../shared/utils/local_time.dart';

/// Food delivery (one checkout, possibly several vendors) or an errand.
enum RiderJobKind { food, errand }

/// ONE job as the rider sees it: one entry per CHECKOUT. Internal vendor
/// parts never appear here. Comes from the rider-safe server functions
/// (`rider_job_pool`, `rider_active_jobs`, `rider_history`), which never
/// return fees, the customer's phone/email or matric number.
class RiderJob {
  const RiderJob({
    required this.id,
    required this.kind,
    this.status = '',
    this.deliveryLocation,
    this.studentNote,
    this.vendorNames = const [],
    this.stopCount = 1,
    this.createdAt,
    this.acceptedAt,
    this.endedAt,
    this.wasCancelled = false,
    this.cancelledByStudent = false,
    this.amount,
    this.category,
    this.pickupLocation,
    this.itemDescription,
    this.isGift = false,
  });

  factory RiderJob.fromJson(Map<String, dynamic> m) {
    final kind =
        m['kind'] == 'errand' ? RiderJobKind.errand : RiderJobKind.food;
    return RiderJob(
      id: m['id'] as String,
      kind: kind,
      status: m['status'] as String? ?? '',
      deliveryLocation: m['delivery_location'] as String?,
      studentNote: m['student_note'] as String?,
      vendorNames: ((m['vendor_names'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
      stopCount: (m['stop_count'] as num?)?.toInt() ?? 1,
      createdAt: parseServerTime(m['created_at']),
      acceptedAt: parseServerTime(m['accepted_at']),
      endedAt: parseServerTime(m['ended_at']),
      wasCancelled: m['was_cancelled'] as bool? ?? false,
      cancelledByStudent: m['cancelled_by_student'] as bool? ?? false,
      amount: (m['amount'] as num?)?.toDouble(),
      category: m['category'] as String?,
      pickupLocation: m['pickup_location'] as String?,
      itemDescription: m['item_description'] as String?,
      isGift: m['is_gift'] == true,
    );
  }

  final String id;
  final RiderJobKind kind;
  final String status;
  final String? deliveryLocation;
  final String? studentNote;
  final List<String> vendorNames;
  final int stopCount;
  final DateTime? createdAt;
  final DateTime? acceptedAt;

  /// History only: the server's completed_at / cancelled_at (local time).
  final DateTime? endedAt;
  final bool wasCancelled;
  final bool cancelledByStudent;

  /// History only: the final food price the rider set. Never a fee.
  final double? amount;
  final String? category;
  final String? pickupLocation;
  final String? itemDescription;

  /// A food job paid for by one student and delivered to another.
  final bool isGift;

  bool get isFood => kind == RiderJobKind.food;
  bool get isErrand => kind == RiderJobKind.errand;
  String get shortId => '#${id.substring(0, 8).toUpperCase()}';
}

/// The Jobs tab: food and errand jobs that can be accepted.
class RiderPool {
  const RiderPool({this.groups = const [], this.errands = const []});

  factory RiderPool.fromJson(Map<String, dynamic> m) => RiderPool(
        groups: ((m['groups'] as List?) ?? const [])
            .map((e) => RiderJob.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        errands: ((m['errands'] as List?) ?? const [])
            .map((e) => RiderJob.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  final List<RiderJob> groups;
  final List<RiderJob> errands;

  bool get isEmpty => groups.isEmpty && errands.isEmpty;
}

/// Read-only details of a finished job (name + location only — no phone,
/// no email, no matric number).
class RiderJobDetail {
  const RiderJobDetail({
    required this.id,
    required this.kind,
    required this.status,
    this.acceptedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelledByStudent = false,
    this.customerName,
    this.deliveryLocation,
    this.amount,
    this.category,
    this.pickupLocation,
    this.itemDescription,
  });

  factory RiderJobDetail.fromJson(Map<String, dynamic> m) => RiderJobDetail(
        id: m['id'] as String,
        kind: m['kind'] == 'errand' ? RiderJobKind.errand : RiderJobKind.food,
        status: m['status'] as String? ?? '',
        acceptedAt: parseServerTime(m['accepted_at']),
        completedAt: parseServerTime(m['completed_at']),
        cancelledAt: parseServerTime(m['cancelled_at']),
        cancelledByStudent: m['cancelled_by_student'] as bool? ?? false,
        customerName: m['customer_name'] as String?,
        deliveryLocation: m['delivery_location'] as String?,
        amount: (m['amount'] as num?)?.toDouble(),
        category: m['category'] as String?,
        pickupLocation: m['pickup_location'] as String?,
        itemDescription: m['item_description'] as String?,
      );

  final String id;
  final RiderJobKind kind;
  final String status;
  final DateTime? acceptedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final bool cancelledByStudent;
  final String? customerName;
  final String? deliveryLocation;
  final double? amount;
  final String? category;
  final String? pickupLocation;
  final String? itemDescription;

  bool get wasCancelled => status == 'cancelled';
  String get shortId => '#${id.substring(0, 8).toUpperCase()}';
}

/// What the Home "Active jobs" card does when tapped.
enum ActiveJobsTarget { chooser, food, errands }

/// Both kinds ⇒ show a chooser. Only one kind ⇒ skip it and open that list.
/// None ⇒ open the food list, which shows its own empty state.
ActiveJobsTarget activeJobsTarget({required int food, required int errands}) {
  if (food > 0 && errands > 0) return ActiveJobsTarget.chooser;
  if (errands > 0) return ActiveJobsTarget.errands;
  return ActiveJobsTarget.food;
}

/// The assigned rider's view of one of their food jobs, from
/// `rider_group_detail` — status, drop-off and note only. It has no PIN and
/// no fees: riders can no longer read the underlying tables.
class RiderGroupDetail {
  const RiderGroupDetail({
    required this.id,
    required this.status,
    this.deliveryLocation,
    this.studentNote,
    this.cancelledByStudent = false,
    this.finalAmount,
    this.completedAt,
    this.cancelledAt,
  });

  factory RiderGroupDetail.fromJson(Map<String, dynamic> m) => RiderGroupDetail(
        id: m['id'] as String,
        status: DeliveryGroupStatus.fromString(m['status'] as String? ?? ''),
        deliveryLocation: m['delivery_location'] as String?,
        studentNote: m['student_note'] as String?,
        cancelledByStudent: m['cancelled_by_student'] as bool? ?? false,
        finalAmount: (m['final_amount'] as num?)?.toDouble(),
        completedAt: parseServerTime(m['completed_at']),
        cancelledAt: parseServerTime(m['cancelled_at']),
      );

  final String id;
  final DeliveryGroupStatus status;
  final String? deliveryLocation;
  final String? studentNote;
  final bool cancelledByStudent;
  final double? finalAmount;
  final DateTime? completedAt;
  final DateTime? cancelledAt;

  bool get isTerminal =>
      status == DeliveryGroupStatus.completed ||
      status == DeliveryGroupStatus.cancelled;
}
