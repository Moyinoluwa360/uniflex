/// Display helpers for timestamps (Pack 4B).
///
/// Every timestamp is stored as `timestamptz` (UTC on the wire). Dart's
/// `DateTime.parse` of "…+00:00" gives a UTC value whose `.hour` is the UTC
/// hour — showing it as-is put every time one hour behind Lagos. Always
/// convert with [toLocal] before reading hour/day, which is what these
/// helpers do.
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// "14:05" in the phone's local time.
String formatLocalTime(DateTime dt) {
  final l = dt.toLocal();
  return '${_two(l.hour)}:${_two(l.minute)}';
}

/// "7 Nov 2026, 14:05" in the phone's local time.
String formatLocalDateTime(DateTime dt) {
  final l = dt.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}, ${formatLocalTime(l)}';
}

/// "Today 14:05" / "Yesterday 14:05" / "7 Nov 2026, 14:05" (local time).
String formatLocalRelative(DateTime dt, {DateTime? now}) {
  final l = dt.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(l.year, l.month, l.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today ${formatLocalTime(l)}';
  if (diff == 1) return 'Yesterday ${formatLocalTime(l)}';
  return formatLocalDateTime(l);
}

/// Parses an ISO timestamp from the server into the phone's local time.
DateTime? parseServerTime(Object? raw) {
  if (raw == null) return null;
  return DateTime.tryParse(raw.toString())?.toLocal();
}
