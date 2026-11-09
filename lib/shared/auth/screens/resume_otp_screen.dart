import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/otp/phone_otp_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/auth/app_auth_header.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../widgets/inputs/app_otp_field.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../validators.dart';
import 'complete_profile_screen.dart';
import '../../widgets/notice/app_inline_notice.dart';
import '../../theme/app_icons.dart';

/// LEGACY (pre-Pack-5 accounts only). Shown by [AuthGate] when a user from the
/// old 2-step flow returns to the app mid-signup: their
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
    // If we already know the phone, auto-send the OTP immediately so the
    // user lands directly on the code-entry phase (no interstitial).
    if (widget.phone != null) {
      _resolvedPhone = widget.phone;
      // Auto-send after first frame to avoid calling setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
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
      final result =
          await ref.read(phoneOtpServiceProvider).sendOtp(_resolvedPhone!);
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
    final c = context.colors;

    // The one pinned action depends on the phase (A/B send, C verify).
    final Widget primary;
    if (_pinId != null) {
      primary = AppButton(
        label: 'Verify',
        icon: AppIcons.success,
        isLoading: _isVerifying,
        onPressed: _verify,
      );
    } else if (_resolvedPhone == null) {
      primary = AppButton(
        label: 'Send Code',
        icon: Icons.send_outlined,
        isLoading: _isSending,
        onPressed: _pinId == null ? _sendCode : null,
      );
    } else {
      primary = AppButton(
        label: 'Send Code',
        icon: Icons.send_outlined,
        isLoading: _isSending,
        onPressed: _sendCode,
      );
    }

    return AppAuthScaffold(
      header: AppAuthHeader.compact(
        title: 'Verify Phone Number',
        subtitle: 'Verify your phone',
        backIcon: AppIcons.close,
        backTooltip: 'Cancel sign-up',
        onBack: () => ref.read(authServiceProvider).signOut(),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 28),
          Text(
            'We need to verify your phone number to continue.',
            style: AppTypography.meta(c),
          ),
          const SizedBox(height: 20),

          // ── Error banner ──────────────────────────────────────────
          if (_errorText != null && _pinId == null) ...[
            AppInlineNotice(isError: true, text: _errorText!),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Phase A: phone number unknown → ask for it ────────────
          if (_resolvedPhone == null)
            Form(
              key: _phoneFormKey,
              child: AppTextField(
                large: true,
                controller: _phoneController,
                label: 'Phone number',
                hint: '08012345678',
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                prefixIcon: AppIcons.phone,
                validator: AuthValidators.phone,
              ),
            ),

          // ── Phase B: phone known, OTP not yet sent → confirm + send
          if (_resolvedPhone != null && _pinId == null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.control),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.phone, size: 22, color: c.textSecondary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      "We'll send a new code to $_resolvedPhone",
                      style: AppTypography.body(c),
                    ),
                  ),
                ],
              ),
            ),

          // ── Phase C: OTP sent → show input + verify ───────────────
          if (_pinId != null) ...[
            Text(
              'Enter the code sent to $_resolvedPhone.',
              style: AppTypography.meta(c),
            ),
            const SizedBox(height: 20),
            AppOtpField(
              controller: _codeController,
              length: 6,
              errorText: _errorText,
            ),
            const SizedBox(height: AppSpacing.md),
            Center(
              child: AppButton(
                label: _isSending ? 'Resending…' : 'Resend code',
                variant: AppButtonVariant.text,
                size: AppButtonSize.small,
                expand: false,
                onPressed: _isSending ? null : _resend,
              ),
            ),
          ],
        ],
      ),
      footer: AppPinnedFooter(primary: primary),
    );
  }
}
