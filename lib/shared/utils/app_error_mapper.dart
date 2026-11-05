import 'package:flutter/foundation.dart';

/// Maps any exception/error to a short, friendly, user-facing string.
/// NEVER returns raw Postgres text, table names, stack traces, etc.
class AppErrorMapper {
  static String map(dynamic error) {
    final raw = error?.toString() ?? '';
    if (raw.contains('INSUFFICIENT_BALANCE') || raw.contains('insufficient_balance')) {
      return 'Not enough balance. Please top up your wallet.';
    }
    if (raw.contains('INVALID_PIN') || raw.contains('invalid_pin') || raw.contains('Incorrect PIN')) {
      return 'Incorrect PIN. Please try again.';
    }
    if (raw.contains('PIN_LOCKED') || raw.contains('pin_locked')) {
      return 'Too many wrong attempts — PIN is locked for 15 minutes.';
    }
    if (raw.contains('PIN_NOT_SET') || raw.contains('pin_not_set')) {
      return 'Please set a transaction PIN first.';
    }
    if (raw.contains('Already paid') || raw.contains('already paid') || raw.contains('DUPLICATE_REFERENCE') || raw.contains('commitment_paid')) {
      return 'This has already been paid.';
    }
    if (raw.contains('ORDER_ALREADY_ACCEPTED')) {
      return 'This job was just taken by another rider.';
    }
    if (raw.contains('TOTAL_MISMATCH')) {
      return 'Prices changed while you were checking out. Please review and retry.';
    }
    if (raw.contains('PRODUCT_UNAVAILABLE')) {
      return 'One item in your cart is no longer available.';
    }
    if (raw.contains('WALLET_NOT_FOUND')) {
      return 'Wallet not found. Please contact support.';
    }
    if (raw.contains('SocketException') || raw.contains('ClientException') || raw.contains('Connection refused') || raw.contains('NetworkException') || raw.contains('No internet') || raw.contains('Failed host lookup')) {
      return 'No internet connection. Please try again.';
    }
    if (raw.contains('crypt')) {
      return 'Server configuration error. Please contact support.';
    }
    // Always log the full error to debug console.
    debugPrint('[AppError] $raw');
    return 'Something went wrong. Please try again.';
  }
}
