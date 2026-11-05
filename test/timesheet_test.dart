import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/screens/reports_screen.dart';
import 'package:vigil/services/reporting_engine.dart';
import 'package:vigil/services/timesheet_calculator.dart';
import 'package:vigil/widgets/app_shell.dart';

import 'preview/preview_data.dart';

// A one-week pay period: Monday 2 Nov to Sunday 8 Nov 2026.
final _from = DateTime(2026, 11, 2);
final _to = DateTime(2026, 11, 9);
DateTime _at(int day, int h, [int m = 0]) => DateTime(2026, 11, day, h, m);

Employee _employee({String id = 'e1', String name = 'Alice Smith', String role = 'staff'}) => Employee(
      id: id,
      organizationId: 'org',
      email: '$id@example.com',
      fullName: name,
      role: role,
      siteLocation: 'Adelaide CBD',
      createdAt: _from,
    );

Shift _shift(DateTime start, DateTime end, {String emp = 'e1'}) => Shift(
      id: 'shift-$emp-$start',
      organizationId: 'org',
      employeeId: emp,
      siteLocation: 'Adelaide CBD',
      startTime: start,
      endTime: end,
      createdAt: _from,
    );

ClockEvent _punch(String type, DateTime at, {String emp = 'e1'}) => ClockEvent(
      id: '$emp-$type-$at',
      organizationId: 'org',
      employeeId: emp,
      eventType: type,
      eventTime: at,
      createdAt: at,
    );

List<ClockEvent> _worked(DateTime clockIn, DateTime clockOut, {String emp = 'e1'}) =>
    [_punch('clock_in', clockIn, emp: emp), _punch('clock_out', clockOut, emp: emp)];

Map<String, dynamic> _break(DateTime start, DateTime? end, {String emp = 'e1'}) => {
      'employee_id': emp,
      'start_time': start.toIso8601String(),
      'end_time': end?.toIso8601String(),
    };

ExceptionRecord _exception(String status, {String emp = 'e1'}) => ExceptionRecord(
      id: 'x-$status',
      organizationId: 'org',
      employeeId: emp,
      exceptionType: 'late_clock_in',
      severity: 'medium',
      status: status,
      createdAt: _from,
    );

List<TimesheetRow> _calculate({
  List<Employee>? employees,
  List<ClockEvent> events = const [],
  List<Shift> shifts = const [],
  List<Map<String, dynamic>> breaks = const [],
  List<ExceptionRecord> exceptions = const [],
  int allowance = 30,
}) =>
    TimesheetCalculator.calculate(
      employees: employees ?? [_employee()],
      events: events,
      shifts: shifts,
      breaks: breaks,
      exceptions: exceptions,
      allowedOvertimeMinutes: allowance,
      from: _from,
      to: _to,
    );

Duration _h(int hours, [int minutes = 0]) => Duration(hours: hours, minutes: minutes);

void main() {
  group('ordinary hours and breaks', () {
    test('a rostered day with no break is all ordinary hours', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 17)), shifts: [_shift(_at(3, 9), _at(3, 17))]).single;
      expect(r.ordinary, _h(8));
      expect(r.overtime, Duration.zero);
      expect(r.breaks, Duration.zero);
      expect(r.needsReview, isFalse);
    });

    test('breaks come off worked time and are totalled', () {
      final r = _calculate(
        events: _worked(_at(3, 9), _at(3, 17)),
        shifts: [_shift(_at(3, 9), _at(3, 17))],
        breaks: [_break(_at(3, 12), _at(3, 12, 30)), _break(_at(3, 15), _at(3, 15, 10))],
      ).single;
      expect(r.ordinary, _h(7, 20));
      expect(r.breaks, _h(0, 40));
    });

    test('several days and split clock-ins add up', () {
      final r = _calculate(
        events: [..._worked(_at(3, 9), _at(3, 12)), ..._worked(_at(3, 13), _at(3, 17)), ..._worked(_at(4, 9), _at(4, 17))],
        shifts: [_shift(_at(3, 9), _at(3, 17)), _shift(_at(4, 9), _at(4, 17))],
      ).single;
      expect(r.ordinary, _h(15));
    });

    test('overlapping break records are not deducted twice', () {
      final r = _calculate(
        events: _worked(_at(3, 9), _at(3, 17)),
        shifts: [_shift(_at(3, 9), _at(3, 17))],
        breaks: [_break(_at(3, 12), _at(3, 13)), _break(_at(3, 12, 30), _at(3, 13, 15))],
      ).single;
      expect(r.breaks, _h(1, 15));
      expect(r.ordinary, _h(6, 45));
    });

    test('a break outside any clocked time is ignored, and one running past clock-out is cut off', () {
      final r = _calculate(
        events: _worked(_at(3, 9), _at(3, 17)),
        shifts: [_shift(_at(3, 9), _at(3, 17))],
        breaks: [_break(_at(3, 7), _at(3, 8)), _break(_at(3, 16, 45), _at(3, 18))],
      ).single;
      expect(r.breaks, _h(0, 15));
      expect(r.ordinary, _h(7, 45));
    });

    test('a break with no end deducts nothing and is noted', () {
      final r = _calculate(
        events: _worked(_at(3, 9), _at(3, 17)),
        shifts: [_shift(_at(3, 9), _at(3, 17))],
        breaks: [_break(_at(3, 12), null)],
      ).single;
      expect(r.ordinary, _h(8));
      expect(r.unfinishedBreaks, 1);
      expect(r.needsReview, isTrue);
    });
  });

  group('overnight shifts', () {
    test('a shift across midnight counts its full length, with a break after midnight', () {
      final r = _calculate(
        events: _worked(_at(3, 22), _at(4, 6)),
        shifts: [_shift(_at(3, 22), _at(4, 6))],
        breaks: [_break(_at(4, 1), _at(4, 1, 30))],
      ).single;
      expect(r.ordinary, _h(7, 30));
      expect(r.breaks, _h(0, 30));
      expect(r.overtime, Duration.zero);
    });

    test('a break spanning midnight is counted once', () {
      final r = _calculate(
        events: _worked(_at(3, 22), _at(4, 6)),
        shifts: [_shift(_at(3, 22), _at(4, 6))],
        breaks: [_break(_at(3, 23, 45), _at(4, 0, 15))],
      ).single;
      expect(r.ordinary, _h(7, 30));
      expect(r.breaks, _h(0, 30));
    });

    test('overtime is measured from the next-day shift end', () {
      final r = _calculate(events: _worked(_at(3, 22), _at(4, 7)), shifts: [_shift(_at(3, 22), _at(4, 6))]).single;
      expect(r.ordinary, _h(8));
      expect(r.overtime, _h(1));
    });

    test('a shift starting on the last night of the period is counted whole in that period', () {
      final r = _calculate(
        events: _worked(_at(8, 22), _at(9, 6)),
        shifts: [_shift(_at(8, 22), _at(9, 6))],
        breaks: [_break(_at(9, 1), _at(9, 1, 30))],
      ).single;
      expect(r.ordinary, _h(7, 30));
      expect(r.breaks, _h(0, 30));
      expect(r.missingClockOuts, 0);
    });

    test('a shift from the previous period is not counted again or reported as a bad punch', () {
      final r = _calculate(events: _worked(_at(1, 22), _at(2, 6)), shifts: [_shift(_at(1, 22), _at(2, 6))]).single;
      expect(r.ordinary, Duration.zero);
      expect(r.missingClockIns, 0);
      expect(r.needsReview, isFalse);
    });

    test('the next period picks up nothing from a shift already counted', () {
      final r = TimesheetCalculator.calculate(
        employees: [_employee()],
        events: _worked(_at(8, 22), _at(9, 6)),
        shifts: [_shift(_at(8, 22), _at(9, 6))],
        breaks: const [],
        exceptions: const [],
        allowedOvertimeMinutes: 30,
        from: _to,
        to: _to.add(const Duration(days: 7)),
      ).single;
      expect(r.ordinary, Duration.zero);
    });
  });

  group('overtime threshold', () {
    final shift = _shift(_at(3, 9), _at(3, 17));

    test('staying past the shift end within the allowance stays ordinary', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 17, 20)), shifts: [shift]).single;
      expect(r.ordinary, _h(8, 20));
      expect(r.overtime, Duration.zero);
    });

    test('exactly at the allowance stays ordinary, as the exception rule does', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 17, 30)), shifts: [shift]).single;
      expect(r.ordinary, _h(8, 30));
      expect(r.overtime, Duration.zero);
    });

    test('past the allowance, all the time after the shift end is overtime', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 17, 45)), shifts: [shift]).single;
      expect(r.ordinary, _h(8));
      expect(r.overtime, _h(0, 45));
    });

    test('follows the organization setting', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 17, 45)), shifts: [shift], allowance: 60).single;
      expect(r.ordinary, _h(8, 45));
      expect(r.overtime, Duration.zero);

      final strict = _calculate(events: _worked(_at(3, 9), _at(3, 17, 5)), shifts: [shift], allowance: 0).single;
      expect(strict.ordinary, _h(8));
      expect(strict.overtime, _h(0, 5));
    });

    test('a break after the shift end comes off overtime, not ordinary hours', () {
      final r = _calculate(
        events: _worked(_at(3, 9), _at(3, 19)),
        shifts: [shift],
        breaks: [_break(_at(3, 18), _at(3, 18, 30))],
      ).single;
      expect(r.ordinary, _h(8));
      expect(r.overtime, _h(1, 30));
      expect(r.breaks, _h(0, 30));
    });

    test('clocking back in after the shift end counts only that time as overtime', () {
      final r = _calculate(events: [..._worked(_at(3, 9), _at(3, 17)), ..._worked(_at(3, 18), _at(3, 19))], shifts: [shift]).single;
      expect(r.ordinary, _h(8));
      expect(r.overtime, _h(1));
    });

    test('time between two rostered shifts in a day is not overtime', () {
      final r = _calculate(
        events: _worked(_at(3, 8), _at(3, 18)),
        shifts: [_shift(_at(3, 8), _at(3, 12)), _shift(_at(3, 14), _at(3, 18))],
      ).single;
      expect(r.ordinary, _h(10));
      expect(r.overtime, Duration.zero);
    });
  });

  group('punches payroll must check', () {
    test('a clock-in with no clock-out counts no hours and is noted', () {
      final r = _calculate(events: [_punch('clock_in', _at(3, 9))], shifts: [_shift(_at(3, 9), _at(3, 17))]).single;
      expect(r.ordinary, Duration.zero);
      expect(r.missingClockOuts, 1);
      expect(r.notes.single, contains('no clock-out'));
    });

    test('two clock-ins in a row: only the second pairs with the clock-out', () {
      final r = _calculate(
        events: [_punch('clock_in', _at(3, 9)), ..._worked(_at(4, 9), _at(4, 17))],
        shifts: [_shift(_at(4, 9), _at(4, 17))],
      ).single;
      expect(r.ordinary, _h(8));
      expect(r.missingClockOuts, 1);
    });

    test('a clock-out with no clock-in counts no hours and is noted', () {
      final r = _calculate(events: [_punch('clock_out', _at(3, 17))]).single;
      expect(r.ordinary, Duration.zero);
      expect(r.missingClockIns, 1);
      expect(r.notes.single, contains('no clock-in'));
    });

    test('hours with no shift nearby are ordinary, never overtime, and noted', () {
      final r = _calculate(events: _worked(_at(3, 9), _at(3, 12, 30))).single;
      expect(r.ordinary, _h(3, 30));
      expect(r.overtime, Duration.zero);
      expect(r.unrostered, _h(3, 30));
      expect(r.notes.single, contains('3.50h'));
    });
  });

  group('rows and exceptions', () {
    test('one row per employee, by name, without mixing up their hours', () {
      final rows = _calculate(
        employees: [_employee(id: 'e2', name: 'Bob Jones'), _employee(id: 'e1', name: 'alice Smith'), _employee(id: 'e3', name: 'Cara Idle')],
        events: [..._worked(_at(3, 9), _at(3, 17), emp: 'e1'), ..._worked(_at(3, 9), _at(3, 13), emp: 'e2')],
        shifts: [_shift(_at(3, 9), _at(3, 17), emp: 'e1'), _shift(_at(3, 9), _at(3, 13), emp: 'e2')],
      );
      expect(rows.map((r) => r.employee.id), ['e1', 'e2', 'e3']);
      expect(rows.map((r) => r.ordinary), [_h(8), _h(4), Duration.zero]);
    });

    test('pending and acknowledged exceptions are open; resolved and ignored are not', () {
      final r = _calculate(exceptions: [
        _exception('pending'),
        _exception('acknowledged'),
        _exception('resolved'),
        _exception('ignored'),
        _exception('pending', emp: 'someone-else'),
      ]).single;
      expect(r.openExceptions, 2);
      expect(r.needsReview, isTrue);
    });
  });

  group('exports', () {
    final row = TimesheetRow(
      employee: _employee(name: '=Alice "Al" Smith'),
      ordinary: _h(37, 30),
      overtime: _h(2, 15),
      breaks: _h(2, 30),
      openExceptions: 1,
    );

    test('CSV has decimal hours, the flag and a safe name', () {
      final lines = ReportingEngine().buildTimesheetCsv([row], firstDay: _from, lastDay: DateTime(2026, 11, 8)).split('\r\n');
      expect(lines.first, contains('"Ordinary hours","Overtime hours","Break hours","Open exceptions"'));
      expect(lines[1], startsWith('"2026-11-02","2026-11-08","\'=Alice ""Al"" Smith"'));
      expect(lines[1], contains('"37.50","2.25","2.50","1","Yes"'));
    });

    test('PDF builds with the Unicode font', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final bytes = await ReportingEngine().buildTimesheetPdf([row], organizationName: 'Org', period: '2 Nov 2026 – 8 Nov 2026');
      expect(String.fromCharCodes(bytes), contains('Roboto'));
    });
  });

  group('who can export', () {
    test('staff are refused before anything is fetched', () {
      expect(
        () => ReportingEngine().fetchTimesheet(_employee(role: 'staff'), from: _from, to: _to),
        throwsA(isA<StateError>()),
      );
    });

    test('the Reports route is open to managers only', () {
      expect(canAccessPath(_employee(role: 'staff'), '/reports'), isFalse);
      for (final role in ['owner', 'admin', 'system_admin', 'manager', 'hr']) {
        expect(canAccessPath(_employee(role: role), '/reports'), isTrue, reason: role);
      }
    });

    group('Reports screen', () {
      setUpAll(() async {
        SharedPreferences.setMockInitialValues({});
        await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'test');
      });

      Future<void> pump(WidgetTester tester, String role) async {
        previewRole = role;
        tester.view.physicalSize = const Size(1366, 860);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(ProviderScope(
          overrides: previewOverrides,
          child: const MaterialApp(home: ReportsScreen()),
        ));
        await tester.pump();
      }

      testWidgets('managers get the timesheet export', (tester) async {
        await pump(tester, 'manager');
        expect(find.text('Export timesheets'), findsOneWidget);
        expect(find.text('Download CSV'), findsNWidgets(2));
        expect(find.text('Download PDF'), findsNWidgets(2));
      });

      testWidgets('staff do not', (tester) async {
        await pump(tester, 'staff');
        expect(find.text('Export timesheets'), findsNothing);
      });
    });
  });
}
