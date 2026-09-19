import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth/auth_providers.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/buttons/primary_button.dart';
import '../../widgets/inputs/app_text_field.dart';

/// Forgot Password — Step 2: enter the 6-digit code emailed to
/// [email], then set a new password. On success this establishes a
/// recovery session and sets the password in one flow; AuthGate then
/// picks up the now-signed-in session on its own (see
/// ARCHITECTURE.md — "Why nothing calls Navigator.push after
/// login/signup/logout").
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email});

  final String email;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_passwordController.text != _confirmController.text) {
      setState(() => _errorText = 'Passwords do not match');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      await auth.verifyPasswordResetOtp(
        email: widget.email,
        token: _codeController.text.trim(),
      );
      await auth.updatePassword(_passwordController.text);
      // No navigation — AuthGate swaps to the right shell on its own now
      // that a valid session exists.
    } on AuthException catch (e) {
      setState(() => _errorText = e.message);
    } catch (_) {
      setState(() => _errorText = 'Invalid or expired code. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset Password')),
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
                  'Check your email',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'We sent a 6-digit code to ${widget.email}. Enter it '
                  'below along with your new password.',
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
                  controller: _codeController,
                  label: '6-digit code',
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  prefixIcon: Icons.pin_outlined,
                  validator: (v) => (v == null || v.trim().length != 6)
                      ? 'Enter the 6-digit code'
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _passwordController,
                  label: 'New password',
                  obscureText: _obscure,
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    icon: Icon(_obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) {
                    if (v == null || v.length < 8) {
                      return 'At least 8 characters';
                    }
                    if (!RegExp(r'\d').hasMatch(v)) {
                      return 'Include at least one digit';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _confirmController,
                  label: 'Confirm new password',
                  obscureText: _obscure,
                  prefixIcon: Icons.lock_outline,
                  validator: (v) =>
                      (v ?? '').isEmpty ? 'Confirm your new password' : null,
                ),
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Reset Password',
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
