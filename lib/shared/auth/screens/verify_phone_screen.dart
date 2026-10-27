import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/otp/phone_otp_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_bar/uniflex_app_bar.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import 'complete_profile_screen.dart';

/// Step 1b — the OTP half of Step One. The account isn't considered
/// created until the code entered here is confirmed by Termii; the
/// `phone-otp` Edge Function records `phone`/`phone_verified_at` on the
/// profiles stub row once it does, and this screen then hands off to
/// [CompleteProfileScreen] (Step Two).
class VerifyPhoneScreen extends ConsumerStatefulWidget {
  const VerifyPhoneScreen({
    super.key,
    required this.phone,
    required this.pinId,
  });

  final String phone;
  final String pinId;

  @override
  ConsumerState<VerifyPhoneScreen> createState() => _VerifyPhoneScreenState();
}

class _VerifyPhoneScreenState extends ConsumerState<VerifyPhoneScreen> {
  final _codeController = TextEditingController();

  late String _pinId = widget.pinId;
  bool _isVerifying = false;
  bool _isResending = false;
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length < 6) {
      setState(() => _errorText = 'Enter the 6-digit code we sent you');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      // The Edge Function verifies with Termii and, on success, records
      // phone/phone_verified_at itself using the service role. The client
      // deliberately no longer writes those columns — see the note in
      // phone_otp_service.dart.
      final verified = await ref.read(phoneOtpServiceProvider).verifyOtp(
            pinId: _pinId,
            pin: code,
            phoneNumber: widget.phone,
          );

      if (!verified) {
        setState(() => _errorText = 'That code is incorrect. Try again.');
        return;
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
      );
    } on OtpException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _isResending = true;
      _errorText = null;
    });
    try {
      final result = await ref
          .read(phoneOtpServiceProvider)
          .sendOtp(widget.phone);
      setState(() => _pinId = result.pinId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Code resent.')));
      }
    } on OtpException catch (e) {
      setState(() => _errorText = e.message);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryInk = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkInkSecondary
        : AppColors.mediumGrey;

    return Scaffold(
      appBar: const UniflexAppBar(title: 'Verify Phone Number'),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Enter the code we sent',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'We sent a verification code to ${widget.phone}.',
                style: textTheme.bodyMedium?.copyWith(color: secondaryInk),
              ),
              const SizedBox(height: AppSpacing.xl),
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(
                      color: colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 20,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          _errorText!,
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              AppTextField(
                controller: _codeController,
                label: 'Verification code',
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                prefixIcon: Icons.sms_outlined,
                maxLength: 6,
              ),
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Verify',
                icon: Icons.check_circle_outline,
                isLoading: _isVerifying,
                onPressed: _verify,
              ),
              const SizedBox(height: AppSpacing.md),
              TextButton(
                onPressed: _isResending ? null : _resend,
                child: Text(_isResending ? 'Resending…' : 'Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
