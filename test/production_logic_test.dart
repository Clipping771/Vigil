import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/models/geofence_zone.dart';
import 'package:vigil/models/leave_request.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/providers/settings_provider.dart';
import 'package:vigil/services/agent_actions.dart';
import 'package:vigil/services/agent_context.dart';
import 'package:vigil/services/agent_service.dart';
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

  group('PDF export', () {
    test('embeds a Unicode font so dashes in descriptions render', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await ReportingEngine().buildPdf([
        ExceptionRecord(
          id: 'x',
          organizationId: 'org-1',
          employeeId: 'e1',
          employeeName: 'Test staff',
          exceptionType: 'late_clock_in',
          severity: 'medium',
          status: 'pending',
          description: 'Clocked in 17 min late — shift started at 9:15 PM',
          createdAt: DateTime(2026, 11, 1, 21, 33),
        ),
      ], organizationName: 'Org', period: '2 Oct 2026 – 1 Nov 2026');
      expect(String.fromCharCodes(bytes), contains('Roboto'));
    });
  });

  group('Vigil AI', () {
    ClockEvent punch(String emp, String type, DateTime at) => ClockEvent(
        id: '$emp-$type-$at', organizationId: 'org-1', employeeId: emp, eventType: type, eventTime: at, isGeofenced: true, createdAt: at);

    test('reply parser separates the action line and strips markdown', () {
      final r = parseAgentReply('**Bob** is on shift.\nACTION: {"type":"navigate","path":"/rosters"}');
      expect(r.text, 'Bob is on shift.');
      expect(r.action, {'type': 'navigate', 'path': '/rosters'});
      expect(parseAgentReply('Just text').action, isNull);
      final legacy = parseAgentReply('{"action":"toggle_theme","payload":"dark"}');
      expect(legacy.action, {'type': 'theme', 'mode': 'dark'});
      expect(parseAgentReply('{"action":"chat","payload":"Hello"}').text, 'Hello');
    });

    test('context includes live status, hours worked and shifts from real data', () {
      final now = DateTime(2026, 11, 2, 12);
      final manager = _employee('manager');
      final bob = _employee('staff');
      final text = formatAgentContext(
        me: manager,
        settings: const AppSettings(),
        now: now,
        data: AgentData(
          organizationName: 'Acme',
          employees: [manager, bob],
          shifts: [_shift('s1', bob.id, DateTime(2026, 11, 2, 9), DateTime(2026, 11, 2, 17))],
          events: [
            punch(bob.id, 'clock_in', DateTime(2026, 11, 1, 9)),
            punch(bob.id, 'clock_out', DateTime(2026, 11, 1, 17)),
            punch(bob.id, 'clock_in', DateTime(2026, 11, 2, 9)),
          ],
          breaks: [
            {'employee_id': bob.id, 'start_time': DateTime(2026, 11, 1, 12).toIso8601String(),
             'end_time': DateTime(2026, 11, 1, 12, 30).toIso8601String(), 'duration_minutes': 30},
          ],
        ),
      );
      expect(text, contains('Organization: Acme'));
      expect(text, contains('Test staff | CLOCKED IN'));
      expect(text, contains('Not clocked in: Test manager'));
      expect(text, contains('breaks 30m | worked 7h30m')); // 1 Nov: 8h minus 30 min break
      expect(text, contains('Test staff | 10h30m')); // 7h30m + 3h so far today
      expect(text, contains('(TODAY) | 09:00-17:00 (8h00m) | Test staff | Site | IN PROGRESS'));
    });

    test('staff context says it is limited to their own records', () {
      final staff = _employee('staff');
      final text = formatAgentContext(
          me: staff, settings: const AppSettings(), now: DateTime(2026, 11, 2), data: AgentData(organizationName: 'Acme', employees: [staff]));
      expect(text, contains("only this user's own records"));
      expect(text, isNot(contains('## Staff')));
    });

    test('proposal lines are parsed and hidden from the reply', () {
      final r = parseAgentReply('I prepared it.\nPROPOSE: {"type":"approve_leave","id":"abcd1234"}\nPROPOSE: {"type":"remove_shift","id":"ef567890"}');
      expect(r.text, 'I prepared it.');
      expect(r.proposals.map((p) => p['type']), ['approve_leave', 'remove_shift']);
    });

    group('proposals need a real record and permission', () {
      final manager = _employee('manager');
      final bob = _employee('staff');
      LeaveRequest leave(String id, String status) => LeaveRequest(
          id: id, employeeId: bob.id, leaveType: 'annual', startDate: DateTime(2026, 11, 4), endDate: DateTime(2026, 11, 6), status: status);
      final data = AgentData(
        organizationName: 'Acme',
        employees: [manager, bob],
        leave: [leave('aaaa1111-0000', 'pending'), leave('bbbb2222-0000', 'approved')],
      );

      test('manager gets a card written from the real record', () {
        final r = resolveProposals([{'type': 'approve_leave', 'id': 'aaaa1111'}], manager, data);
        expect(r.rejected, isEmpty);
        expect(r.proposals.single.summary, 'Approve annual leave for Test staff: Wed 4 Nov 2026 to Fri 6 Nov 2026 (3 days)');
        expect(r.proposals.single.args['id'], 'aaaa1111-0000');
      });

      test('unknown, already decided or unauthorised changes are rejected', () {
        final r = resolveProposals([
          {'type': 'approve_leave', 'id': 'zzzz9999'},
          {'type': 'approve_leave', 'id': 'bbbb2222'},
          {'type': 'delete_everything'},
        ], manager, data);
        expect(r.proposals, isEmpty);
        expect(r.rejected, hasLength(3));
        expect(resolveProposals([{'type': 'approve_leave', 'id': 'aaaa1111'}], bob, data).rejected.single, contains('only managers'));
      });

      test('overnight shifts end the next day', () {
        final r = resolveProposals([
          {'type': 'add_shift', 'employee_id': bob.id, 'start': '2026-11-03T22:00', 'end': '2026-11-03T06:00', 'site': 'Plant'},
        ], manager, data);
        expect(r.proposals.single.summary, 'Add shift for Test staff: Tue 3 Nov 2026 22:00-06:00 at Plant');
        expect(DateTime.parse(r.proposals.single.args['end']), DateTime(2026, 11, 4, 6));
      });
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

  group('Site QR codes', () {
    test('carry the zone and its secret', () {
      expect(siteQrPayload('zone-1', 'secret'), 'vigil:site:zone-1:secret');
    });

    test('old and current codes match their own zone only', () {
      expect(isSiteQrFor('vigil:site:zone-1:secret', 'zone-1'), isTrue);
      expect(isSiteQrFor('vigil:site:zone-1', 'zone-1'), isTrue);
      expect(isSiteQrFor('vigil:site:zone-12:secret', 'zone-1'), isFalse);
      expect(isSiteQrFor('something else', 'zone-1'), isFalse);
    });
  });
}
