import 'package:flutter/material.dart';

/// Standard content card: theme surface, hairline border, soft shadow.
///
/// [blurRadius] and [opacity] are accepted for backwards compatibility and
/// ignored — backdrop blur was expensive on web and muddy in light mode.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final double blurRadius;
  final double opacity;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const PremiumCard({
    super.key,
    required this.child,
    this.blurRadius = 15.0,
    this.opacity = 0.1,
    this.padding = const EdgeInsets.all(20.0),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = BorderRadius.circular(16);

    return Material(
      color: theme.colorScheme.surface,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: theme.colorScheme.outline),
            boxShadow: isDark
                ? null
                : [BoxShadow(color: const Color(0xFF0F172A).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 2))],
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
