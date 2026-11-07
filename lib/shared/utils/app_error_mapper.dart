import 'package:flutter/foundation.dart';

import '../auth/signup/signup_api.dart';

/// Maps any exception/error to a short, friendly, user-facing string.
/// NEVER returns raw Postgres text, table names, stack traces, etc.
class AppErrorMapper {
  static String map(dynamic error) {
    // Pack 5: sign-up refusals already carry their own friendly wording.
    if (error is SignupException) return error.message;
    final raw = error?.toString() ?? '';
    if (raw.contains('TimeoutException')) {
      return 'That took too long. Check your connection and try again.';
    }
    // Rider job cap (enforced in the accept functions).
    if (raw.contains('ACTIVE_JOB_LIMIT')) {
      return 'You already have 3 active jobs. Finish one before accepting another.';
    }
    if (raw.contains('Incorrect delivery PIN')) {
      return 'Incorrect delivery PIN. Please check with the customer.';
    }
    if (raw.contains('Already accepted by another rider') ||
        raw.contains('Order already taken') ||
        raw.contains('could not obtain lock')) {
      return 'This job was just taken by another rider.';
    }
    if (raw.contains('This order is already finished')) {
      return 'This delivery is already finished.';
    }
    if (raw.contains('INSUFFICIENT_BALANCE') ||
        raw.contains('insufficient_balance')) {
      return 'Not enough balance. Please top up your wallet.';
    }
    if (raw.contains('INVALID_PIN') ||
        raw.contains('invalid_pin') ||
        raw.contains('Incorrect PIN')) {
      return 'Incorrect PIN. Please try again.';
    }
    if (raw.contains('PIN_LOCKED') || raw.contains('pin_locked')) {
      return 'Too many wrong attempts — PIN is locked for 15 minutes.';
    }
    if (raw.contains('PIN_NOT_SET') || raw.contains('pin_not_set')) {
      return 'Please set a transaction PIN first.';
    }
    if (raw.contains('Already paid') ||
        raw.contains('already paid') ||
        raw.contains('DUPLICATE_REFERENCE') ||
        raw.contains('commitment_paid')) {
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
    if (raw.contains('LOCATION_DETAILS_REQUIRED')) {
      return 'Please describe exactly where to deliver.';
    }
    if (raw.contains('LOCATION_NOT_FOUND')) {
      return 'That delivery location is no longer available. Pick another.';
    }
    if (raw.contains('VENDOR_NOT_FOUND') || raw.contains('PRODUCT_NOT_FOUND')) {
      return 'One of the items in your cart is no longer on the menu.';
    }
    if (raw.contains('PACK_OVER_CAPACITY') || raw.contains('PACK_MISMATCH')) {
      return 'There is a problem with your packs. Please rebuild them and try again.';
    }
    if (raw.contains('PICKUP_UNIFLEX_ONLY')) {
      return 'Pickup is only available for Uniflex orders.';
    }
    if (raw.contains('SCHEDULE_IN_PAST')) {
      return 'That pickup time has passed. Pick a new time.';
    }
    if (raw.contains('EMPTY_ORDER')) {
      return 'Your cart is empty.';
    }
    if (raw.contains('CATEGORY_NOT_FOUND')) {
      return 'That service is not available right now.';
    }
    if (raw.contains('DESCRIPTION_REQUIRED')) {
      return 'Please describe what you need done.';
    }
    if (raw.contains('IDEMPOTENCY_KEY_IN_USE')) {
      return 'Something went wrong. Please go back and try again.';
    }
    if (raw.contains('GIFT_SELF')) {
      return "You can't send a gift to yourself.";
    }
    if (raw.contains('GIFT_RECIPIENT_NOT_FOUND')) {
      return 'No student found with that email.';
    }
    if (raw.contains('GIFT_MESSAGE_TOO_LONG')) {
      return 'Your gift message is too long (200 characters at most).';
    }
    if (raw.contains('INVALID_PHONE')) {
      return 'Enter a valid number, like 0803 123 4567 or +234 803 123 4567.';
    }
    if (raw.contains('SocketException') ||
        raw.contains('ClientException') ||
        raw.contains('Connection refused') ||
        raw.contains('NetworkException') ||
        raw.contains('No internet') ||
        raw.contains('Failed host lookup')) {
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
