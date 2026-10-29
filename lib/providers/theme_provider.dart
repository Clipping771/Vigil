import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app offers exactly two appearances.
enum AppTheme { light, dark }

extension AppThemeLabel on AppTheme {
  String get label => this == AppTheme.light ? 'Light' : 'Dark';
  IconData get icon => this == AppTheme.light ? Icons.light_mode_outlined : Icons.dark_mode_outlined;
}

class ThemeState {
  final AppTheme currentTheme;
  final ThemeData themeData;

  ThemeState({required this.currentTheme, required this.themeData});

  bool get isDark => currentTheme == AppTheme.dark;
}

final themeProvider = StateNotifierProvider<ThemeNotifier, ThemeState>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<ThemeState> {
  static const _prefsKey = 'app_theme';

  ThemeNotifier() : super(_stateFor(_systemDefault())) {
    _restore();
  }

  static AppTheme _systemDefault() =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark ? AppTheme.dark : AppTheme.light;

  static ThemeState _stateFor(AppTheme t) => ThemeState(currentTheme: t, themeData: buildAppTheme(t));

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = AppTheme.values.where((t) => t.name == prefs.getString(_prefsKey)).firstOrNull;
      if (saved != null && mounted) state = _stateFor(saved);
    } catch (_) {
      // Preferences unavailable (e.g. private browsing) — keep the system default.
    }
  }

  void setTheme(AppTheme theme) {
    state = _stateFor(theme);
    SharedPreferences.getInstance().then((p) => p.setString(_prefsKey, theme.name)).ignore();
  }

  void toggle() => setTheme(state.isDark ? AppTheme.light : AppTheme.dark);
}

// ==========================================
// MATERIAL 3 THEME
// ==========================================

/// Brand seed. Material 3 derives the full tonal palette for light and dark.
const _seed = Color(0xFF1A73E8);

/// Semantic status colours (Material 3 "custom colors"), harmonised per mode.
@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  final Color success, onSuccess, successContainer, onSuccessContainer;
  final Color warning, onWarning, warningContainer, onWarningContainer;
  final Color info, infoContainer, onInfoContainer;

  const StatusColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  static const light = StatusColors(
    success: Color(0xFF146C2E),
    onSuccess: Colors.white,
    successContainer: Color(0xFFC4EED0),
    onSuccessContainer: Color(0xFF072711),
    warning: Color(0xFF8A5100),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFDDB4),
    onWarningContainer: Color(0xFF2B1700),
    info: Color(0xFF00639B),
    infoContainer: Color(0xFFCEE5FF),
    onInfoContainer: Color(0xFF001D33),
  );

  static const dark = StatusColors(
    success: Color(0xFF6DD58C),
    onSuccess: Color(0xFF00391A),
    successContainer: Color(0xFF0F5223),
    onSuccessContainer: Color(0xFFC4EED0),
    warning: Color(0xFFFFB95C),
    onWarning: Color(0xFF482900),
    warningContainer: Color(0xFF693C00),
    onWarningContainer: Color(0xFFFFDDB4),
    info: Color(0xFF96CCFF),
    infoContainer: Color(0xFF004A77),
    onInfoContainer: Color(0xFFCEE5FF),
  );

  @override
  StatusColors copyWith() => this;

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) => t < 0.5 ? this : (other as StatusColors? ?? this);
}

ThemeData buildAppTheme(AppTheme theme) {
  final isDark = theme == AppTheme.dark;
  final brightness = isDark ? Brightness.dark : Brightness.light;
  final generated = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  // Light mode is pure white everywhere (no tinted grey surfaces); dark mode
  // uses Google's neutral dark surfaces.
  final scheme = isDark
      ? generated.copyWith(
          primary: const Color(0xFF8AB4F8),
          onPrimary: const Color(0xFF062E6F),
          primaryContainer: const Color(0xFF0B57D0),
          onPrimaryContainer: Colors.white,
          secondaryContainer: const Color(0xFF004A77),
          onSecondaryContainer: const Color(0xFFD3E3FD),
          surface: const Color(0xFF131314),
          onSurface: const Color(0xFFE3E3E3),
          onSurfaceVariant: const Color(0xFFC4C7C5),
          surfaceContainerLowest: const Color(0xFF0E0E0F),
          surfaceContainerLow: const Color(0xFF1B1B1C),
          surfaceContainer: const Color(0xFF1E1F20),
          surfaceContainerHigh: const Color(0xFF282A2C),
          surfaceContainerHighest: const Color(0xFF333537),
          outline: const Color(0xFF444746),
          outlineVariant: const Color(0xFF333537),
          surfaceTint: Colors.transparent,
        )
      : generated.copyWith(
          primary: _seed,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFD3E3FD),
          onPrimaryContainer: const Color(0xFF041E49),
          secondaryContainer: const Color(0xFFE8F0FE),
          onSecondaryContainer: const Color(0xFF0B57D0),
          surface: Colors.white,
          onSurface: const Color(0xFF1F1F1F),
          onSurfaceVariant: const Color(0xFF5F6368),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Colors.white,
          surfaceContainer: Colors.white,
          surfaceContainerHigh: Colors.white,
          surfaceContainerHighest: const Color(0xFFF1F3F4),
          outline: const Color(0xFFDADCE0),
          outlineVariant: const Color(0xFFE8EAED),
          surfaceTint: Colors.transparent,
          error: const Color(0xFFD93025),
        );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final textTheme = GoogleFonts.robotoTextTheme(base.textTheme).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );
  final shape12 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: textTheme,
    extensions: [theme == AppTheme.dark ? StatusColors.dark : StatusColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: scheme.surfaceTint,
      elevation: 0,
      scrolledUnderElevation: 3,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: isDark ? scheme.surfaceContainerLow : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: textTheme.headlineSmall,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size(64, 40), textStyle: textTheme.labelLarge),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(minimumSize: const Size(64, 40), textStyle: textTheme.labelLarge),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: textTheme.labelLarge)),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
    listTileTheme: ListTileThemeData(shape: shape12),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating, width: 440),
    navigationDrawerTheme: NavigationDrawerThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.secondaryContainer,
      tileHeight: 52,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
    ),
  );
}
