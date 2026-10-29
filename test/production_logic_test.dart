import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/services/exception_engine.dart';
import 'package:vigil/services/reporting_engine.dart';
import 'package:vigil/widgets/app_shell.dart';
import 'package:vigil/widgets/auth_layout.dart';

Employee _employee(String role) => Employee(
      id: 'e-$role',
      organizationId: 'org-1',
      email: '$role@example.com',
      fullName: 'Test $role',
      role: role,
      createdAt: DateTime(2026),
    );

Shift _shift(String id, String employeeId, DateTime start, DateTime end) => Shift(
      id: id,
      organizationId: 'org-1',
      employeeId: employeeId,
      siteLocation: 'Site',
      startTime: start,
      endTime: end,
      createdAt: start,
    );

void main() {
  group('Route access', () {
    test('staff cannot open manager or admin pages', () {
      final staff = _employee('staff');
      expect(canAccessPath(staff, '/dashboard'), isTrue);
      expect(canAccessPath(staff, '/leave'), isTrue);
      expect(canAccessPath(staff, '/staff'), isFalse);
      expect(canAccessPath(staff, '/reports'), isFalse);
      expect(canAccessPath(staff, '/admin'), isFalse);
    });

    test('managers see management pages but not the platform console', () {
      final manager = _employee('manager');
      expect(canAccessPath(manager, '/staff'), isTrue);
      expect(canAccessPath(manager, '/geofence'), isTrue);
      expect(canAccessPath(manager, '/admin'), isFalse);
      expect(canAccessPath(_employee('system_admin'), '/admin'), isTrue);
    });
  });

  group('Rest breach detection', () {
    final day = DateTime(2026, 10, 29);

    test('only compares shifts belonging to the same employee', () {
      // Bob's late shift sits between Alice's two shifts and must not hide her breach.
      final aliceLate = _shift('a1', 'alice', day.subtract(const Duration(hours: 8)), day.subtract(const Duration(hours: 1)));
      final bob = _shift('b1', 'bob', day.subtract(const Duration(minutes: 30)), day.add(const Duration(hours: 2)));
      final aliceEarly = _shift('a2', 'alice', day.add(const Duration(hours: 5)), day.add(const Duration(hours: 12)));

      final result = ExceptionEngine.detectRestBreaches(
        upcomingShifts: [bob, aliceEarly],
        pastShifts: [aliceLate, bob],
        organizationId: 'org-1',
      );

      expect(result, hasLength(1));
      expect(result.single.employeeId, 'alice');
      expect(result.single.shiftId, 'a2');
    });

    test('does not flag a 10+ hour gap', () {
      final first = _shift('s1', 'alice', day.subtract(const Duration(hours: 9)), day.subtract(const Duration(hours: 1)));
      final second = _shift('s2', 'alice', day.add(const Duration(hours: 9)), day.add(const Duration(hours: 17)));
      final result = ExceptionEngine.detectRestBreaches(
        upcomingShifts: [second],
        pastShifts: [first],
        organizationId: 'org-1',
      );
      expect(result, isEmpty);
    });
  });

  group('CSV export', () {
    test('escapes quotes and neutralises spreadsheet formulas', () {
      final csv = ReportingEngine().buildCsv([
        ExceptionRecord(
          id: 'x',
          organizationId: 'org-1',
          employeeId: 'e1',
          employeeName: '=HYPERLINK("http://evil")',
          exceptionType: 'roster_breach',
          severity: 'high',
          status: 'pending',
          description: 'Said "hello"',
          createdAt: DateTime(2026, 10, 29, 9),
        ),
      ]);
      final dataRow = csv.split('\r\n')[1];
      expect(dataRow, contains('"\'=HYPERLINK(""http://evil"")"'));
      expect(dataRow, contains('"Said ""hello"""'));
    });
  });

  group('Form validation', () {
    test('email', () {
      expect(validateEmail('person@company.com'), isNull);
      expect(validateEmail('not-an-email'), isNotNull);
      expect(validateEmail(''), isNotNull);
    });

    test('new password strength', () {
      expect(validateNewPassword('short1'), isNotNull);
      expect(validateNewPassword('longpassword'), isNotNull);
      expect(validateNewPassword('correct horse 9'), isNull);
    });
  });
}
