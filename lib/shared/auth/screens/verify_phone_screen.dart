import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/auth/app_auth_header.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/inputs/app_otp_field.dart';
import '../signup/signup_api.dart';
import '../signup/signup_flow_controller.dart';
import '../../theme/app_icons.dart';

/// Step 2 of sign-up — "Verify your phone". Shows the masked number and a
/// 6-digit field. Resend is disabled for 60 s with a visible countdown;
/// "Change number" goes back to step 1 with everything still filled in.
///
/// A correct code does NOT create an account: the server hands back a
/// short-lived proof which the controller keeps with the draft, and the
/// flow moves to step 3. No navigation happens here — the host swaps the
/// step when the controller says so.
class VerifyPhoneScreen extends StatefulWidget {
  const VerifyPhoneScreen({super.key, required this.controller});

  final SignupFlowController controller;

  @override
  State<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends State<VerifyPhoneScreen> {
  final _codeController = TextEditingController();
  Timer? _ticker;
  String? _localError;

  SignupFlowController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    // Redraws the countdown once a second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _localError = 'Enter the 6-digit code we sent you');
      return;
    }
    setState(() => _localError = null);
    final ok = await _c.verify(code);
    if (!ok && mounted) _codeController.clear();
  }

  Future<void> _resend() async {
    setState(() => _localError = null);
    final ok = await _c.resend();
    if (ok && mounted) {
      _codeController.clear();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('New code sent.')));
    }
  }

  String _countdown(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final busy = _c.busy;
    final wait = _c.cooldownRemaining;
    final error = _localError ?? _c.error;

    return AppAuthScaffold(
      header: AppAuthHeader.compact(
        title: 'Verify your\nphone',
        onBack: busy ? null : _c.changeNumber,
        step: 2,
        totalSteps: 3,
        stepLabel: '2 / 3',
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 28),
          Text(
            'We sent a 6-digit code to ${maskPhone(_c.phoneE164)}.',
            key: const ValueKey('masked-phone'),
            style: AppTypography.meta(c),
          ),
          const SizedBox(height: 20),
          AppOtpField(
            controller: _codeController,
            length: 6,
            errorText: error,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: AppButton(
              key: const ValueKey('resend'),
              label: wait > 0
                  ? 'Resend code in ${_countdown(wait)}'
                  : 'Resend code',
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              expand: false,
              onPressed: (busy || wait > 0) ? null : _resend,
            ),
          ),
          Center(
            child: AppButton(
              key: const ValueKey('change-number'),
              label: 'Change number',
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              expand: false,
              onPressed: busy ? null : _c.changeNumber,
            ),
          ),
        ],
      ),
      footer: AppPinnedFooter(
        primary: AppButton(
          label: 'Verify',
          icon: AppIcons.success,
          isLoading: busy,
          onPressed: busy ? null : _verify,
        ),
      ),
    );
  }
}
