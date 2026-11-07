/// Nigerian phone numbers → the international digits WhatsApp's `wa.me`
/// links need (country code, no "+", no spaces): `2348031234567`.
///
/// Accepts `08031234567`, `0803 123 4567`, `0803-123-4567`, `+2348031234567`,
/// `+234 803 123 4567` and `2348031234567`. Returns null when the input is
/// not a valid Nigerian mobile-length number. The server runs the same rule
/// (`_normalize_ng_phone`) and is the authority; this copy only lets the
/// form complain before saving.
String? normalizeNigerianPhone(String? raw) {
  final v = (raw ?? '').replaceAll(RegExp(r'[\s\-\(\)\.\+]'), '');
  if (v.isEmpty) return null;
  if (RegExp(r'^0[0-9]{10}$').hasMatch(v)) return '234${v.substring(1)}';
  if (RegExp(r'^234[0-9]{10}$').hasMatch(v)) return v;
  return null;
}

/// The `wa.me` link for [digits] (international digits) with a prefilled
/// message: "Hi, this is <name>." plus the short order id when the chat was
/// opened from an order.
Uri buildSupportWhatsappUri({
  required String digits,
  String? name,
  String? orderShortId,
}) {
  final who = (name ?? '').trim();
  final buffer =
      StringBuffer('Hi, this is ${who.isEmpty ? 'a Uniflex student' : who}.');
  final order = (orderShortId ?? '').trim();
  if (order.isNotEmpty) {
    buffer.write(' Order #${order.replaceFirst(RegExp(r'^#'), '')}.');
  }
  return Uri.https('wa.me', '/$digits', {'text': buffer.toString()});
}
