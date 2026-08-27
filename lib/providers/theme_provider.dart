import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppTheme {
  deepSpace,
  cyberpunk,
  arcticLight,
  forestGlow,
  crimsonVoid
}

class ThemeState {
  final AppTheme currentTheme;
  final ThemeData themeData;

  ThemeState({required this.currentTheme, required this.themeData});
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeState> {
  ThemeNotifier() : super(ThemeState(currentTheme: AppTheme.deepSpace, themeData: _buildDeepSpaceTheme()));

  void setTheme(AppTheme theme) {
    ThemeData newThemeData;
    switch (theme) {
      case AppTheme.deepSpace:
        newThemeData = _buildDeepSpaceTheme();
        break;
      case AppTheme.cyberpunk:
        newThemeData = _buildCyberpunkTheme();
        break;
      case AppTheme.arcticLight:
        newThemeData = _buildArcticLightTheme();
        break;
      case AppTheme.forestGlow:
        newThemeData = _buildForestGlowTheme();
        break;
      case AppTheme.crimsonVoid:
        newThemeData = _buildCrimsonVoidTheme();
        break;
    }
    state = ThemeState(currentTheme: theme, themeData: newThemeData);
  }
}

// ==========================================
// THEME DEFINITIONS
// ==========================================

ThemeData _buildDeepSpaceTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      background: Color(0xFF0F172A),
      surface: Color(0xFF1E293B),
      primary: Color(0xFF3B82F6),
      secondary: Color(0xFF00E5FF),
      tertiary: Color(0xFF7C3AED),
      error: Color(0xFFEF4444),
      onBackground: Colors.white,
      onSurface: Colors.white,
    ),
    useMaterial3: true,
  );
}

ThemeData _buildCyberpunkTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      background: Color(0xFF09090B),
      surface: Color(0xFF18181B),
      primary: Color(0xFFFF003C), // Cyberpunk Red/Pink
      secondary: Color(0xFF00F0FF), // Neon Cyan
      tertiary: Color(0xFFFCEE09), // Cyber Yellow
      error: Color(0xFFFF003C),
      onBackground: Color(0xFFE4E4E7),
      onSurface: Color(0xFFE4E4E7),
    ),
    useMaterial3: true,
  );
}

ThemeData _buildArcticLightTheme() {
  return ThemeData(
    brightness: Brightness.light,
    colorScheme: const ColorScheme.light(
      background: Color(0xFFF8FAFC),
      surface: Colors.white,
      primary: Color(0xFF0EA5E9),
      secondary: Color(0xFF38BDF8),
      tertiary: Color(0xFF0284C7),
      error: Color(0xFFEF4444),
      onBackground: Color(0xFF0F172A),
      onSurface: Color(0xFF0F172A),
    ),
    useMaterial3: true,
  );
}

ThemeData _buildForestGlowTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      background: Color(0xFF061810),
      surface: Color(0xFF0D291D),
      primary: Color(0xFF10B981),
      secondary: Color(0xFF34D399),
      tertiary: Color(0xFFFBBF24), // Gold accent
      error: Color(0xFFEF4444),
      onBackground: Color(0xFFD1FAE5),
      onSurface: Color(0xFFD1FAE5),
    ),
    useMaterial3: true,
  );
}

ThemeData _buildCrimsonVoidTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      background: Color(0xFF180A0A),
      surface: Color(0xFF2B1212),
      primary: Color(0xFFDC2626),
      secondary: Color(0xFFEF4444),
      tertiary: Color(0xFF7F1D1D),
      error: Color(0xFFF87171),
      onBackground: Color(0xFFFEE2E2),
      onSurface: Color(0xFFFEE2E2),
    ),
    useMaterial3: true,
  );
}
