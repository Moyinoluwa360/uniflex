import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth/auth_providers.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';
import '../validators.dart';
import 'reset_password_screen.dart';

/// Forgot Password — Step 1: enter the account email, request a 6-digit
/// recovery code. Reachable from the Login screen.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    final email = _emailController.text.trim();

    try {
      await ref.read(authServiceProvider).sendPasswordResetOtp(email);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResetPasswordScreen(email: email),
        ),
      );
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
      appBar: AppBar(title: const Text('Forgot Password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.screenGutter),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Reset your password',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Enter the email on your account and we\'ll send you a '
                  '6-digit code to reset your password.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: AppSpacing.xl),
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
                  textInputAction: TextInputAction.done,
                  prefixIcon: Icons.mail_outline,
                  validator: AuthValidators.email,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Send Code',
                  isLoading: _isLoading,
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
