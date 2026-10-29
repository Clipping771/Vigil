import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_layout.dart';

/// Self-service sign-up for a new organization. The organization and owner
/// profile are created server-side by `link_current_user` on first sign-in.
class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _sentTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(authProvider.notifier).clearError());
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final email = _emailController.text.trim();
      final outcome = await ref.read(authProvider.notifier).signUp(
            email: email,
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
            companyName: _companyController.text.trim(),
          );
      if (outcome == SignUpOutcome.confirmationRequired && mounted) {
        setState(() => _sentTo = email);
      }
    } on AuthException {
      // Shown via authProvider.error.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    if (_sentTo != null) {
      return AuthLayout(
        title: 'Check your inbox',
        subtitle: 'One more step to set up your workspace.',
        form: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormMessage(
              'We sent a confirmation link to $_sentTo. Open it to verify your email, then sign in — '
              'your organization will be created automatically.',
              isError: false,
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/login'), child: const Text('Go to sign in')),
          ],
        ),
      );
    }

    return AuthLayout(
      title: 'Create your workspace',
      subtitle: 'Start a Vigil organization. You\'ll be its owner and can invite your team.',
      form: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (authState.error != null) ...[
                FormMessage(authState.error!),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _companyController,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.organizationName],
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Company name', prefixIcon: Icon(Icons.business_outlined)),
                validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your company name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'Work email', prefixIcon: Icon(Icons.mail_outline)),
                validator: validateEmail,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters, with a letter and a number',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: validateNewPassword,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: const InputDecoration(labelText: 'Confirm password', prefixIcon: Icon(Icons.lock_outline)),
                validator: (v) => v != _passwordController.text ? 'Passwords do not match' : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: (_busy || authState.isLoading) ? null : _submit,
                child: (_busy || authState.isLoading)
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create workspace'),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Already have an account?'),
                  TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
