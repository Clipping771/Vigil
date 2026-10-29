import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';

enum _Mode { signIn, activate, reset }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  _Mode _mode = _Mode.signIn;
  bool _obscure = true;
  bool _busy = false;
  String? _notice;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _setMode(_Mode mode) {
    ref.read(authProvider.notifier).clearError();
    setState(() {
      _mode = mode;
      _notice = null;
      _passwordController.clear();
      _confirmPasswordController.clear();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final auth = ref.read(authProvider.notifier);

    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      switch (_mode) {
        case _Mode.signIn:
          // Navigation happens via the router guard once the profile loads.
          await auth.login(email, password);
        case _Mode.activate:
          final outcome = await auth.signUp(email: email, password: password);
          if (outcome == SignUpOutcome.confirmationRequired && mounted) {
            setState(() {
              _mode = _Mode.signIn;
              _notice = 'We sent a confirmation link to $email. Open it, then sign in with your new password.';
            });
          }
        case _Mode.reset:
          await auth.sendPasswordReset(email);
          if (mounted) {
            setState(() {
              _mode = _Mode.signIn;
              _notice = 'If an account exists for $email, a password reset link is on its way.';
            });
          }
      }
    } on AuthException {
      // Error is surfaced through authProvider.error.
    } catch (e) {
      if (mounted) setState(() => _notice = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final theme = Theme.of(context);
    final loading = _busy || authState.isLoading;

    final (title, subtitle, cta) = switch (_mode) {
      _Mode.signIn => ('Welcome back', 'Sign in to your Vigil workspace.', 'Sign in'),
      _Mode.activate => (
          'Activate your account',
          'Your administrator has added you to Vigil. Choose a password to get started.',
          'Activate account'
        ),
      _Mode.reset => ('Reset password', 'Enter your work email and we\'ll send you a reset link.', 'Send reset link'),
    };

    return AuthLayout(
      title: title,
      subtitle: subtitle,
      form: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (authState.error != null) ...[
                FormMessage(authState.error!),
                const SizedBox(height: 16),
              ] else if (_notice != null) ...[
                FormMessage(_notice!, isError: false),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: _mode == _Mode.reset ? TextInputAction.done : TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.mail_outline)),
                validator: validateEmail,
                onFieldSubmitted: _mode == _Mode.reset ? (_) => _submit() : null,
              ),
              if (_mode != _Mode.reset) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  autofillHints: [_mode == _Mode.signIn ? AutofillHints.password : AutofillHints.newPassword],
                  textInputAction: _mode == _Mode.signIn ? TextInputAction.done : TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _mode == _Mode.signIn ? 'Password' : 'New password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: _mode == _Mode.signIn
                      ? (v) => (v == null || v.isEmpty) ? 'Password is required' : null
                      : validateNewPassword,
                  onFieldSubmitted: _mode == _Mode.signIn ? (_) => _submit() : null,
                ),
              ],
              if (_mode == _Mode.activate) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                  validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                  onFieldSubmitted: (_) => _submit(),
                ),
              ],
              if (_mode == _Mode.signIn)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: () => _setMode(_Mode.reset), child: const Text('Forgot password?')),
                )
              else
                const SizedBox(height: 20),
              FilledButton(
                onPressed: loading ? null : _submit,
                child: loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(cta),
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              if (_mode == _Mode.signIn) ...[
                OutlinedButton(
                  onPressed: () => _setMode(_Mode.activate),
                  child: const Text('First time here? Activate your account'),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New organization?', style: theme.textTheme.bodyMedium),
                    TextButton(onPressed: () => context.go('/register'), child: const Text('Create a workspace')),
                  ],
                ),
              ] else
                TextButton(onPressed: () => _setMode(_Mode.signIn), child: const Text('Back to sign in')),
            ],
          ),
        ),
      ),
    );
  }
}
