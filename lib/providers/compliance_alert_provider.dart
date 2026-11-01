import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/exception_record.dart';
import 'auth_provider.dart';
import 'exception_provider.dart';
import 'theme_provider.dart';

/// Open (pending) compliance issues the signed-in user should notice: their
/// own for staff, the organization's for managers (the exception list is
/// already scoped that way).
class ComplianceAlertState {
  final ComplianceAlert level;
  final List<ExceptionRecord> open;

  const ComplianceAlertState(this.level, this.open);

  static const none = ComplianceAlertState(ComplianceAlert.none, []);

  int get serious => open.where((e) => e.isCritical || e.isHigh).length;

  /// Changes whenever the set of open issues changes (used to re-show a dismissed banner).
  String get key => (open.map((e) => e.id).toList()..sort()).join(',');
}

final complianceAlertProvider = Provider<ComplianceAlertState>((ref) {
  final signedIn = ref.watch(authProvider.select((s) => s.currentUser != null));
  if (!signedIn) return ComplianceAlertState.none;
  final open = ref.watch(exceptionStateProvider.select((s) => s.pendingExceptions));
  if (open.isEmpty) return ComplianceAlertState.none;
  final level = open.any((e) => e.isCritical || e.isHigh) ? ComplianceAlert.danger : ComplianceAlert.warning;
  return ComplianceAlertState(level, open);
});

/// The theme the app uses right now: light/dark, recoloured by open
/// compliance issues unless the user turned that off.
final appThemeProvider = Provider<ThemeData>((ref) {
  final themeState = ref.watch(themeProvider);
  final enabled = ref.watch(complianceColorsProvider);
  final level = ref.watch(complianceAlertProvider.select((a) => a.level));
  if (!enabled || level == ComplianceAlert.none) return themeState.themeData;
  return buildAppTheme(themeState.currentTheme, alert: level);
});

/// The open-issue set the user last dismissed the banner for.
final dismissedComplianceBannerProvider = StateProvider<String?>((ref) => null);
