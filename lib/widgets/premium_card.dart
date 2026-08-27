import 'dart:ui';
import 'package:flutter/material.dart';

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
    
    // For dark themes, we want a slight white/primary tint. For light themes, a slight dark/primary tint.
    final baseColor = isDark ? theme.colorScheme.primary : theme.colorScheme.primary;
    final borderColor = isDark ? Colors.white : Colors.black;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurRadius, sigmaY: blurRadius),
          child: Container(
            decoration: BoxDecoration(
              color: baseColor.withOpacity(opacity),
              borderRadius: BorderRadius.circular(24.0),
              border: Border.all(
                color: borderColor.withOpacity(0.15),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: -5,
                ),
              ],
            ),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
