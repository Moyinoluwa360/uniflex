import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../widgets/buttons/app_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/auth/app_auth_header.dart';
import '../../widgets/auth/auth_scaffold.dart';
import '../../services/auth/auth_providers.dart';
import '../validators.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';
import '../../widgets/notice/app_inline_notice.dart';
import '../../theme/app_icons.dart';

/// The one login screen every role uses — Student, Rider, and Admin
/// alike. Which shell a person lands on after this is decided by their
/// `profiles.role`, not by anything picked on this screen. There is
/// deliberately no "sign up as Rider/Admin" anywhere on this screen or
/// reachable from it — Staff accounts are invite-only, seeded by hand in
/// Supabase (see supabase/schema.sql). [AuthGate] reacts to a successful
/// sign-in on its own; this screen does not navigate on success.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await ref.read(authServiceProvider).signInWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      // No navigation here — AuthGate watches auth state and swaps to
      // the correct role shell (or Step Two, if onboarding never
      // finished) on its own.
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return AppAuthScaffold(
      header: const AppAuthHeader.login(
        headline: 'Welcome back',
        subtitle: 'Log in to order food, book deliveries and send errands.',
        chips: [
          AuthHeaderChip(AppIcons.food, 'Food'),
          AuthHeaderChip(AppIcons.delivery, 'Deliveries'),
          AuthHeaderChip(AppIcons.errand, 'Errands'),
        ],
      ),
      caption: Text("Redeemer's University", style: AppTypography.caption(c)),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 30),
            if (_errorText != null) ...[
              AppInlineNotice(isError: true, text: _errorText!),
              const SizedBox(height: AppSpacing.md),
            ],
            AppTextField(
              large: true,
              controller: _emailController,
              label: 'Email address',
              scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 260),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              prefixIcon: AppIcons.mail,
              validator: AuthValidators.email,
            ),
            const SizedBox(height: 14),
            AppTextField(
              large: true,
              controller: _passwordController,
              label: 'Password',
              scrollPadding: const EdgeInsets.fromLTRB(20, 20, 20, 180),
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              prefixIcon: AppIcons.lock,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? AppIcons.eye : AppIcons.eyeOff,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              validator: (v) =>
                  (v ?? '').isEmpty ? 'Enter your password' : null,
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton(
                label: 'Forgot password?',
                variant: AppButtonVariant.text,
                size: AppButtonSize.small,
                expand: false,
                onPressed: _isLoading
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ForgotPasswordScreen(),
                          ),
                        ),
              ),
            ),
            const SizedBox(height: 12),
            AppButton(
              label: 'Log In',
              isLoading: _isLoading,
              icon: AppIcons.forward,
              onPressed: _submit,
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(child: Divider(height: 1, color: c.border)),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(
                    'New here?',
                    style: AppTypography.sectionLabel(c)
                        .copyWith(color: c.textTertiary),
                  ),
                ),
                Expanded(child: Divider(height: 1, color: c.border)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              variant: AppButtonVariant.secondary,
              label: 'Create Account',
              onPressed: _isLoading
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CreateAccountScreen(),
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
