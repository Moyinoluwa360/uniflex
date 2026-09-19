import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/buttons/secondary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../../widgets/wordmark/uniflex_wordmark.dart';
import '../../services/auth/auth_providers.dart';
import '../validators.dart';
import 'create_account_screen.dart';
import 'forgot_password_screen.dart';

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
      await ref
          .read(authServiceProvider)
          .signInWithEmail(
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
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.xxl),
                const Center(child: UniflexWordmark(fontSize: 40)),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Campus food, delivery, and errands.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_errorText != null) ...[
                  Text(
                    _errorText!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
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
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
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
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Enter your password' : null,
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ForgotPasswordScreen(),
                            ),
                          ),
                    child: const Text('Forgot password?'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Log In',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
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
        ),
      ),
    );
  }
}
