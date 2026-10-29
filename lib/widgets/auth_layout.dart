import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'app_shell.dart';

/// Split-screen frame for the sign-in and sign-up pages: a brand panel on wide
/// screens and a single centered form column on phones.
class AuthLayout extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget form;

  const AuthLayout({super.key, required this.title, required this.subtitle, required this.form});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 960;

    final formColumn = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isWide) ...[
                InkWell(
                  onTap: () => context.go('/'),
                  borderRadius: BorderRadius.circular(8),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BrandMark(size: 32),
                      SizedBox(width: 10),
                      Text('Vigil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
              ],
              Text(title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 28),
              form,
            ],
          ),
        ),
      ),
    );

    if (!isWide) return Scaffold(body: SafeArea(child: formColumn));

    return Scaffold(
      body: Row(
        children: [
          const Expanded(flex: 5, child: _BrandPanel()),
          Expanded(flex: 6, child: formColumn),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(scheme.surfaceContainerLowest, scheme.primary, 0.22)!,
            scheme.surfaceContainerLowest,
          ],
        ),
        border: Border(right: BorderSide(color: scheme.outline)),
      ),
      padding: const EdgeInsets.all(48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => context.go('/'),
            borderRadius: BorderRadius.circular(8),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                BrandMark(size: 36),
                SizedBox(width: 12),
                Text('Vigil', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const Spacer(),
          Text(
            'Workforce attendance and\ncompliance, in real time.',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.25),
          ),
          const SizedBox(height: 28),
          for (final (icon, text) in const [
            (Icons.share_location_outlined, 'Geofenced clock-in with GPS verification'),
            (Icons.calendar_month_outlined, 'Rosters, breaks and leave in one place'),
            (Icons.verified_user_outlined, 'Automatic Fair Work compliance alerts'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant))),
                ],
              ),
            ),
          const Spacer(),
          Text('© ${DateTime.now().year} Vigil', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Inline banner for form-level errors and notices.
class FormMessage extends StatelessWidget {
  final String message;
  final bool isError;
  const FormMessage(this.message, {super.key, this.isError = true});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Icons.error_outline : Icons.mark_email_read_outlined, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: scheme.onSurface, height: 1.35))),
        ],
      ),
    );
  }
}

String? validateEmail(String? v) {
  final value = v?.trim() ?? '';
  if (value.isEmpty) return 'Email is required';
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address';
  return null;
}

String? validateNewPassword(String? v) {
  final value = v ?? '';
  if (value.length < 8) return 'Use at least 8 characters';
  if (!RegExp(r'[A-Za-z]').hasMatch(value) || !RegExp(r'\d').hasMatch(value)) {
    return 'Include at least one letter and one number';
  }
  return null;
}
