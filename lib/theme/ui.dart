import 'package:flutter/material.dart';

/// Theme-aware colour shortcuts so widgets never hardcode light/dark values.
extension UiColors on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;

  /// Foreground (text/icon/border) colour at the given opacity.
  Color fg([double alpha = 1]) => cs.onSurface.withValues(alpha: alpha);

  Color get surfaceHigh => cs.surfaceContainerHigh;
  Color get surfaceLowest => cs.surfaceContainerLowest;
}
