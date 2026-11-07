import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../pin/pin_entry_sheet.dart';
import '../sheets/acknowledgment_sheet.dart';
import '../../services/auth/auth_providers.dart';
import '../../utils/app_error_mapper.dart';

/// Result of [runPaymentFlow].
enum PaymentFlowResult { success, cancelled, failed }

/// Runs the standard payment step:
///   1. acknowledgment sheet (pre-payment warning)
///   2. check / set PIN
///   3. PIN entry sheet
///   4. call [onConfirm] with the entered PIN
///
/// Returns [PaymentFlowResult.success] only when [onConfirm] completes
/// without throwing. [onConfirm] should throw on RPC errors.
///
/// [setSubmitting] is called with true/false around the RPC call so the
/// caller can disable its UI while the payment is in flight.
Future<PaymentFlowResult> runPaymentFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String acknowledgeMessage,
  required String pinTitle,
  required String pinSubtitle,
  required Future<void> Function(String pin) onConfirm,
  required void Function(bool) setSubmitting,
  required void Function(String) onError,
}) async {
  // 1. Acknowledgment.
  final ok =
      await showAcknowledgmentSheet(context, message: acknowledgeMessage);
  if (!ok || !context.mounted) return PaymentFlowResult.cancelled;

  // 2. Check / set PIN.
  final hasPin = await ref.read(profileServiceProvider).hasTransactionPin();
  if (!context.mounted) return PaymentFlowResult.cancelled;

  if (!hasPin) {
    final didSet = await showSetPinSheet(context, ref);
    if (!context.mounted || !didSet) return PaymentFlowResult.cancelled;
  }

  // 3. PIN entry.
  final pin =
      await showEnterPinSheet(context, title: pinTitle, subtitle: pinSubtitle);
  if (pin == null || !context.mounted) return PaymentFlowResult.cancelled;

  // 4. RPC call.
  setSubmitting(true);
  try {
    await onConfirm(pin);
    return PaymentFlowResult.success;
  } catch (e) {
    onError(AppErrorMapper.map(e));
    return PaymentFlowResult.failed;
  } finally {
    setSubmitting(false);
  }
}
