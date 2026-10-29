import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppTheme {
  deepSpace,
  cyberpunk,
  arcticLight,
  forestGlow,
  crimsonVoid,
}

extension AppThemeLabel on AppTheme {
  String get label => switch (this) {
        AppTheme.deepSpace => 'Midnight',
        AppTheme.cyberpunk => 'Graphite',
        AppTheme.arcticLight => 'Light',
        AppTheme.forestGlow => 'Forest',
        AppTheme.crimsonVoid => 'Crimson',
      };
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
  static const _prefsKey = 'app_theme';

  ThemeNotifier() : super(ThemeState(currentTheme: AppTheme.deepSpace, themeData: buildAppTheme(AppTheme.deepSpace))) {
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      final theme = AppTheme.values.where((t) => t.name == saved).firstOrNull;
      if (theme != null && mounted) {
        state = ThemeState(currentTheme: theme, themeData: buildAppTheme(theme));
      }
    } catch (_) {
      // Preferences unavailable (e.g. private browsing) — keep the default.
    }
  }

  void setTheme(AppTheme theme) {
    state = ThemeState(currentTheme: theme, themeData: buildAppTheme(theme));
    SharedPreferences.getInstance().then((p) => p.setString(_prefsKey, theme.name)).ignore();
  }
}

// ==========================================
// DESIGN TOKENS
// ==========================================

class _Palette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color error;
  final Color text;
  final Color textMuted;

  const _Palette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.error,
    required this.text,
    required this.textMuted,
  });
}

const _palettes = {
  AppTheme.deepSpace: _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0B1120),
    surface: Color(0xFF111A2E),
    surfaceHigh: Color(0xFF1A2540),
    border: Color(0xFF243150),
    primary: Color(0xFF4F8CFF),
    secondary: Color(0xFF22D3EE),
    tertiary: Color(0xFF8B5CF6),
    error: Color(0xFFF87171),
    text: Color(0xFFE6EBF5),
    textMuted: Color(0xFF8A96AE),
  ),
  AppTheme.cyberpunk: _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF0A0A0B),
    surface: Color(0xFF141416),
    surfaceHigh: Color(0xFF1E1E22),
    border: Color(0xFF2A2A30),
    primary: Color(0xFFF5F5F7),
    secondary: Color(0xFF38BDF8),
    tertiary: Color(0xFFFACC15),
    error: Color(0xFFF87171),
    text: Color(0xFFEDEDEF),
    textMuted: Color(0xFF8E8E96),
  ),
  AppTheme.arcticLight: _Palette(
    brightness: Brightness.light,
    background: Color(0xFFF6F8FB),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F4F9),
    border: Color(0xFFE2E8F0),
    primary: Color(0xFF2563EB),
    secondary: Color(0xFF0891B2),
    tertiary: Color(0xFF7C3AED),
    error: Color(0xFFDC2626),
    text: Color(0xFF0F172A),
    textMuted: Color(0xFF64748B),
  ),
  AppTheme.forestGlow: _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF07130E),
    surface: Color(0xFF0D1F17),
    surfaceHigh: Color(0xFF142B21),
    border: Color(0xFF1F3B2E),
    primary: Color(0xFF34D399),
    secondary: Color(0xFF5EEAD4),
    tertiary: Color(0xFFFBBF24),
    error: Color(0xFFF87171),
    text: Color(0xFFE3F5EC),
    textMuted: Color(0xFF86A898),
  ),
  AppTheme.crimsonVoid: _Palette(
    brightness: Brightness.dark,
    background: Color(0xFF120A0B),
    surface: Color(0xFF1C1012),
    surfaceHigh: Color(0xFF28171A),
    border: Color(0xFF3A2226),
    primary: Color(0xFFF43F5E),
    secondary: Color(0xFFFB923C),
    tertiary: Color(0xFFA78BFA),
    error: Color(0xFFFCA5A5),
    text: Color(0xFFF7E8EA),
    textMuted: Color(0xFFAA8E93),
  ),
};

ThemeData buildAppTheme(AppTheme theme) {
  final p = _palettes[theme]!;
  final isDark = p.brightness == Brightness.dark;
  final onPrimary = p.primary.computeLuminance() > 0.5 ? const Color(0xFF0B0B0C) : Colors.white;

  final scheme = ColorScheme(
    brightness: p.brightness,
    primary: p.primary,
    onPrimary: onPrimary,
    primaryContainer: p.primary.withValues(alpha: 0.16),
    onPrimaryContainer: p.primary,
    secondary: p.secondary,
    onSecondary: isDark ? const Color(0xFF041014) : Colors.white,
    tertiary: p.tertiary,
    onTertiary: Colors.white,
    error: p.error,
    onError: isDark ? const Color(0xFF1A0505) : Colors.white,
    surface: p.surface,
    onSurface: p.text,
    onSurfaceVariant: p.textMuted,
    surfaceContainerLowest: p.background,
    surfaceContainerLow: p.background,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceHigh,
    surfaceContainerHighest: p.surfaceHigh,
    outline: p.border,
    outlineVariant: p.border.withValues(alpha: 0.6),
  );

  final base = ThemeData(brightness: p.brightness, useMaterial3: true, colorScheme: scheme);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: p.text, displayColor: p.text);
  final radius = BorderRadius.circular(10);

  return base.copyWith(
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    dividerColor: p.border,
    textTheme: textTheme.copyWith(
      headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      headlineSmall: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodySmall: textTheme.bodySmall?.copyWith(color: p.textMuted),
      labelSmall: textTheme.labelSmall?.copyWith(color: p.textMuted, letterSpacing: 0.6),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: p.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: p.text),
      shape: Border(bottom: BorderSide(color: p.border)),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: p.border)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: p.border)),
      titleTextStyle: textTheme.titleLarge,
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.border)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? p.surfaceHigh.withValues(alpha: 0.6) : p.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: p.textMuted),
      labelStyle: TextStyle(color: p.textMuted),
      prefixIconColor: p.textMuted,
      suffixIconColor: p.textMuted,
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.border)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.error)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: p.error, width: 1.5)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.1),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        minimumSize: const Size(0, 44),
        backgroundColor: p.surfaceHigh,
        foregroundColor: p.text,
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: p.border)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        foregroundColor: p.text,
        side: BorderSide(color: p.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.primary,
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surfaceHigh,
      selectedColor: p.primary.withValues(alpha: 0.18),
      side: BorderSide(color: p.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(color: p.text, fontSize: 13),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        side: BorderSide(color: p.border),
        selectedBackgroundColor: p.primary.withValues(alpha: 0.18),
        selectedForegroundColor: p.primary,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.textMuted,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: isDark ? p.surfaceHigh : const Color(0xFF0F172A),
      contentTextStyle: TextStyle(color: isDark ? p.text : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: radius),
      width: 420,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: isDark ? p.surfaceHigh : const Color(0xFF0F172A), borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(color: isDark ? p.text : Colors.white, fontSize: 12),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      selectedIconTheme: IconThemeData(color: p.primary),
      unselectedIconTheme: IconThemeData(color: p.textMuted),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: p.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: p.text, fontWeight: FontWeight.w500)),
    ),
    drawerTheme: DrawerThemeData(backgroundColor: p.surface, surfaceTintColor: Colors.transparent),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.primary),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? onPrimary : p.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.primary : p.surfaceHigh),
      trackOutlineColor: WidgetStatePropertyAll(p.border),
    ),
  );
}
