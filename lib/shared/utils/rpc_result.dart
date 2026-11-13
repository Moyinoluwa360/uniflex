/// Some money RPCs report a PIN problem by RETURNING `{"error": "<CODE>"}`
/// instead of raising (Pack 2): a raised error would roll back the server's
/// failed-PIN counter, so the 5-tries lockout would never trigger.
///
/// [throwIfRpcError] turns that returned error into an exception, so callers
/// keep a single `try / catch` and `AppErrorMapper` shows the friendly text
/// (it matches `INVALID_PIN`, `PIN_LOCKED`, `PIN_NOT_SET`, …).
class RpcErrorException implements Exception {
  const RpcErrorException(this.code);

  /// The server's error code, e.g. `INVALID_PIN`.
  final String code;

  @override
  String toString() => code;
}

/// Throws [RpcErrorException] when [result] is a map with a non-empty
/// `error` value; otherwise returns [result] unchanged.
dynamic throwIfRpcError(dynamic result) {
  if (result is Map) {
    final error = result['error'];
    if (error is String && error.isNotEmpty) {
      throw RpcErrorException(error);
    }
  }
  return result;
}
