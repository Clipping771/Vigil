import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/providers/auth_provider.dart';
import 'package:vigil/providers/compliance_alert_provider.dart';
import 'package:vigil/providers/exception_provider.dart';
import 'package:vigil/providers/theme_provider.dart';

ExceptionRecord _issue(String severity, String status) => ExceptionRecord(
      id: '$severity-$status',
      organizationId: 'org',
      employeeId: 'e1',
      exceptionType: 'late_clock_in',
      severity: severity,
      status: status,
      createdAt: DateTime(2026, 11, 2),
    );

class _Auth extends StateNotifier<AuthState> implements AuthNotifier {
  _Auth() : super(AuthState(initialized: true, currentUser: Employee(id: 'e1', organizationId: 'org', email: 'a@b.c', fullName: 'Bob', role: 'staff', createdAt: DateTime(2026))));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Issues extends ExceptionNotifier {
  _Issues(super.ref, List<ExceptionRecord> issues) {
    state = ExceptionState(allExceptions: issues);
  }
  @override
  Future<void> fetchExceptions({bool silent = false}) async {}
}

ProviderContainer _with(List<ExceptionRecord> issues) => ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => _Auth()),
      exceptionStateProvider.overrideWith((ref) => _Issues(ref, issues)),
    ]);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'test');
  });

  test('alert level follows the most serious open issue', () {
    expect(_with([]).read(complianceAlertProvider).level, ComplianceAlert.none);
    // Reviewed issues do not count.
    expect(_with([_issue('high', 'resolved'), _issue('high', 'acknowledged')]).read(complianceAlertProvider).level, ComplianceAlert.none);
    expect(_with([_issue('medium', 'pending')]).read(complianceAlertProvider).level, ComplianceAlert.warning);
    final c = _with([_issue('low', 'pending'), _issue('critical', 'pending')]);
    expect(c.read(complianceAlertProvider).level, ComplianceAlert.danger);
    expect(c.read(complianceAlertProvider).serious, 1);
  });

  test('open issues recolour the theme unless turned off', () {
    final calm = _with([]);
    final alarmed = _with([_issue('high', 'pending')]);
    final normal = calm.read(appThemeProvider).colorScheme;
    final alert = alarmed.read(appThemeProvider).colorScheme;
    expect(alert.primary, alert.error);
    expect(alert.primary, isNot(normal.primary));
    expect(alert.surface, normal.surface); // Surfaces and text stay readable.

    alarmed.read(complianceColorsProvider.notifier).set(false);
    expect(alarmed.read(appThemeProvider).colorScheme.primary, normal.primary);
  });

  test('warning uses the amber status colour in both modes', () {
    for (final mode in AppTheme.values) {
      final t = buildAppTheme(mode, alert: ComplianceAlert.warning);
      expect(t.colorScheme.primary, t.extension<StatusColors>()!.warning);
      expect(t.appBarTheme.backgroundColor, isNot(t.colorScheme.surface));
    }
  });
}
