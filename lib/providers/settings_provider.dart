import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppSettings {
  final int allowedLateMinutes;
  final int allowedOvertimeMinutes;
  final bool autoReportingEnabled;

  const AppSettings({
    this.allowedLateMinutes = 15,
    this.allowedOvertimeMinutes = 30,
    this.autoReportingEnabled = false,
  });

  AppSettings copyWith({
    int? allowedLateMinutes,
    int? allowedOvertimeMinutes,
    bool? autoReportingEnabled,
  }) {
    return AppSettings(
      allowedLateMinutes: allowedLateMinutes ?? this.allowedLateMinutes,
      allowedOvertimeMinutes: allowedOvertimeMinutes ?? this.allowedOvertimeMinutes,
      autoReportingEnabled: autoReportingEnabled ?? this.autoReportingEnabled,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier() : super(const AppSettings());

  void updateLateMinutes(int minutes) {
    state = state.copyWith(allowedLateMinutes: minutes);
  }

  void updateOvertimeMinutes(int minutes) {
    state = state.copyWith(allowedOvertimeMinutes: minutes);
  }

  void toggleAutoReporting(bool enabled) {
    state = state.copyWith(autoReportingEnabled: enabled);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier();
});
