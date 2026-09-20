import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth/auth_providers.dart';
import '../../services/otp/termii_otp_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/progress/onboarding_progress_bar.dart';
import '../validators.dart';
import 'verify_phone_screen.dart';

/// Step One of Student self-signup — Email, Password, Phone Number only.
/// Google/Apple sign-in is deliberately not built here (deferred past
/// MVP). There is no role picker: this screen only ever creates a
/// Student account — Rider/Admin accounts are invite-only (see
/// supabase/schema.sql).
///
/// On submit: creates the Supabase Auth user, writes the bare profiles
/// stub row, then kicks off Termii phone OTP and hands off to
/// [VerifyPhoneScreen]. The account isn't considered created until that
/// screen's OTP check passes — this screen doesn't touch
/// `currentProfileProvider`/`AuthGate` routing at all.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final e164Phone = AuthValidators.toE164(_phoneController.text);

    try {
      final response = await ref
          .read(authServiceProvider)
          .signUpWithEmail(email: email, password: password);

      final userId = response.user?.id;
      if (userId == null) {
        throw const AuthException(
          'Could not create your account. Try again.',
        );
      }
      if (response.session == null) {
        // The Supabase project still has "Confirm email" turned on —
        // see the setup note in supabase/schema.sql. This app verifies
        // via phone OTP, not an email link, so that setting must be off
        // for sign-in to work right after this step.
        throw const AuthException(
          'Sign-up succeeded but no session was returned — ask whoever '
          'set up the Supabase project to turn off "Confirm email" '
          '(Authentication → Providers → Email).',
        );
      }

      await ref
          .read(profileServiceProvider)
          .createStubProfile(userId: userId, email: email);

      final otpResult = await ref
          .read(termiiOtpServiceProvider)
          .sendOtp(e164Phone);

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              VerifyPhoneScreen(phone: e164Phone, pinId: otpResult.pinId),
        ),
      );
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } on TermiiException catch (e) {
      setState(
        () => _errorText =
            'Account created, but the verification code could not be '
            'sent: ${e.message}',
      );
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OnboardingProgressHeader(step: 1, totalSteps: 2),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Create your\naccount',
                  style: textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Food, deliveries and errands across campus. '
                  'Takes about a minute.',
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
                  controller: _emailController,
                  label: 'Email address',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.mail_outline,
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: '8+ characters, at least one number',
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  validator: AuthValidators.password,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _phoneController,
                  label: 'Phone number',
                  hint: '08012345678',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.phone_outlined,
                  validator: AuthValidators.phone,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward,
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: textTheme.bodyMedium?.copyWith(
                        color: secondaryInk,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('Log in'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
