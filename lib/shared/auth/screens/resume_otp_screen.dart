import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/otp/phone_otp_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/app_bar/uniflex_app_bar.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../validators.dart';
import 'complete_profile_screen.dart';

/// Shown by [AuthGate] when a user returns to the app mid-signup: their
/// auth account exists and they have a profile stub row, but
/// `phone_verified_at` is still null, so they never completed Step 1b.
///
/// Two sub-states:
///   - [phone] is non-null (the stub row has the phone saved) → show it and
///     offer "Send a new code" directly.
///   - [phone] is null (old stub rows before the A2/A3 fix) → ask the user
///     to re-enter their number first.
///
/// On successful OTP verification the screen pushes to [CompleteProfileScreen]
/// (Step Two) and the user carries on normally.
class ResumeOtpScreen extends ConsumerStatefulWidget {
  const ResumeOtpScreen({super.key, required this.phone});

  /// The phone number stored on the profile stub, or null for legacy stubs.
  final String? phone;

  @override
  ConsumerState<ResumeOtpScreen> createState() => _ResumeOtpScreenState();
}

class _ResumeOtpScreenState extends ConsumerState<ResumeOtpScreen> {
  // — phone-entry phase (only used when widget.phone is null) —
  final _phoneController = TextEditingController();
  final _phoneFormKey = GlobalKey<FormState>();

  // — OTP phase —
  final _codeController = TextEditingController();

  String? _resolvedPhone; // set once we know the number to use
  String? _pinId; // set once OTP has been sent

  bool _isSending = false;
  bool _isVerifying = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    // If we already know the phone, pre-resolve it so the UI skips straight
    // to the "Send Code" button.
    if (widget.phone != null) {
      _resolvedPhone = widget.phone;
    }
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    // If no phone resolved yet, validate the form field first.
    if (_resolvedPhone == null) {
      if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
      _resolvedPhone = AuthValidators.toE164(_phoneController.text);
    }

    setState(() {
      _isSending = true;
      _errorText = null;
    });

    try {
      final result = await ref
          .read(phoneOtpServiceProvider)
          .sendOtp(_resolvedPhone!);
      setState(() => _pinId = result.pinId);
    } on OtpException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Could not send the code. Try again.');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
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
      final verified = await ref.read(phoneOtpServiceProvider).verifyOtp(
            pinId: _pinId!,
            pin: code,
            phoneNumber: _resolvedPhone!,
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
      _pinId = null;
      _codeController.clear();
      _errorText = null;
    });
    await _sendCode();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final secondaryInk = Theme.of(context).brightness == Brightness.dark
        ? AppColors.darkInkSecondary
        : AppColors.mediumGrey;

    return Scaffold(
      appBar: UniflexAppBar(
        title: 'Verify Phone Number',
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel sign-up',
          onPressed: () => ref.read(authServiceProvider).signOut(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Resume verification',
                style: textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Your sign-up was interrupted. '
                'Verify your phone number to continue.',
                style: textTheme.bodyMedium?.copyWith(color: secondaryInk),
              ),
              const SizedBox(height: AppSpacing.xl),

              // ── Error banner ──────────────────────────────────────────
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

              // ── Phase A: phone number unknown → ask for it ────────────
              if (_resolvedPhone == null) ...[
                Form(
                  key: _phoneFormKey,
                  child: AppTextField(
                    controller: _phoneController,
                    label: 'Phone number',
                    hint: '08012345678',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    prefixIcon: Icons.phone_outlined,
                    validator: AuthValidators.phone,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Send Code',
                  icon: Icons.send_outlined,
                  isLoading: _isSending,
                  onPressed: _pinId == null ? _sendCode : null,
                ),
              ],

              // ── Phase B: phone known, OTP not yet sent → confirm + send
              if (_resolvedPhone != null && _pinId == null) ...[
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_outlined,
                        size: 20,
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          "We'll send a new code to $_resolvedPhone",
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Send Code',
                  icon: Icons.send_outlined,
                  isLoading: _isSending,
                  onPressed: _sendCode,
                ),
              ],

              // ── Phase C: OTP sent → show input + verify ───────────────
              if (_pinId != null) ...[
                Text(
                  'Enter the code sent to $_resolvedPhone.',
                  style: textTheme.bodyMedium?.copyWith(color: secondaryInk),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                  onPressed: _isSending ? null : _resend,
                  child: Text(_isSending ? 'Resending…' : 'Resend code'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
