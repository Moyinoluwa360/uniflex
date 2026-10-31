/// Shared field validation for the auth/onboarding screens. Pure
/// functions (no BuildContext, no widgets) so they're trivial to unit
/// test and reuse across Step One and any future password-change screen.
abstract final class AuthValidators {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  // Nigerian numbers: accept 0XXXXXXXXXX (11 digits) or already-E.164
  // +234XXXXXXXXXX, since that's what a Redeemer's University student is
  // going to type.
  static final _localPhonePattern = RegExp(r'^0\d{10}$');
  static final _e164PhonePattern = RegExp(r'^\+234\d{10}$');

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email address';
    if (!_emailPattern.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// 8+ characters, at least one digit — enforced per the Phase 1 spec.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'\d').hasMatch(v)) return 'Include at least one number';
    return null;
  }

  /// Strips whitespace, dashes, parentheses, and dots so users can type
  /// phone numbers in any common visual format.
  static String _sanitize(String value) =>
      value.trim().replaceAll(RegExp(r'[\s\-\(\)\.]'), '');

  static String? phone(String? value) {
    final v = _sanitize(value ?? '');
    if (v.isEmpty) return 'Enter your phone number';
    if (!_localPhonePattern.hasMatch(v) && !_e164PhonePattern.hasMatch(v)) {
      return 'Enter a valid Nigerian number, e.g. 08012345678 or +2348012345678';
    }
    return null;
  }

  /// Normalises a Nigerian number to E.164 (`+234...`) for Termii.
  static String toE164(String value) {
    final v = _sanitize(value);
    if (v.startsWith('+234')) return v;
    if (v.startsWith('0')) return '+234${v.substring(1)}';
    return v;
  }

  static String? required(String? value, {required String fieldName}) {
    if ((value ?? '').trim().isEmpty) return 'Enter $fieldName';
    return null;
  }
}
