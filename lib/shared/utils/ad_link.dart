// Helpers for an advertisement's optional web link.
//
// Admin may type a bare domain (`example.com/promo`); we add `https://`.
// Only http and https links are ever stored or opened — anything else
// (`javascript:`, `mailto:`, `ftp://`…) is rejected, and a malformed link
// simply means "no link" rather than an error on the student's phone.

final _explicitScheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');
final _dangerousScheme = RegExp(
    r'^(javascript|data|mailto|tel|sms|file|vbscript):',
    caseSensitive: false);

/// The cleaned http(s) link for [raw], or null when [raw] is empty or not a
/// usable web address.
String? normalizeAdLink(String? raw) {
  var text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  if (RegExp(r'\s').hasMatch(text)) return null;
  if (_dangerousScheme.hasMatch(text)) return null;
  if (_explicitScheme.hasMatch(text)) {
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
      return null;
    }
  } else {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasAuthority) return null;
  final host = uri.host;
  // A real address has a dot ("example.com"); this also catches "https://".
  if (host.isEmpty ||
      !host.contains('.') ||
      host.startsWith('.') ||
      host.endsWith('.')) {
    return null;
  }
  return text;
}

/// Form validator: empty is fine (an ad needs no link); anything typed must
/// be a usable web address.
String? validateAdLink(String? raw) {
  final text = (raw ?? '').trim();
  if (text.isEmpty) return null;
  return normalizeAdLink(text) == null
      ? 'Enter a valid web address, like example.com or https://example.com'
      : null;
}
