import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:vigil/models/employee.dart';
import 'package:vigil/models/leave_calendar.dart';
import 'package:vigil/models/leave_request.dart';
import 'package:vigil/models/public_holiday.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/providers/auth_provider.dart';
import 'package:vigil/providers/leave_calendar_provider.dart';
import 'package:vigil/providers/leave_provider.dart';
import 'package:vigil/providers/roster_provider.dart';
import 'package:vigil/providers/staff_provider.dart';
import 'package:vigil/providers/theme_provider.dart';
import 'package:vigil/screens/leave_screen.dart';

const _me = 'worker';

LeaveRequest _leave(DateTime start, DateTime end, {String employeeId = _me}) => LeaveRequest(
    id: 'l-${start.toIso8601String()}', employeeId: employeeId, leaveType: 'annual', startDate: start, endDate: end, status: 'approved');

Shift _shift(DateTime start, {String employeeId = _me, int hours = 8}) => Shift(
    id: 's-$employeeId-${start.toIso8601String()}',
    organizationId: 'org',
    employeeId: employeeId,
    siteLocation: 'Plant',
    startTime: start,
    endTime: start.add(Duration(hours: hours)),
    createdAt: start);

PublicHoliday _holiday(DateTime date) => PublicHoliday(id: 'h-$date', organizationId: 'org', date: date, name: 'Holiday');

void main() {
  // 2 Nov 2026 is a Monday.
  final mon = DateTime(2026, 11, 2);
  final wed = DateTime(2026, 11, 4);
  final fri = DateTime(2026, 11, 6);
  final sat = DateTime(2026, 11, 7);
  final sun = DateTime(2026, 11, 8);

  group('Weekend shift workers', () {
    test('a rostered Saturday uses leave', () {
      final calendar = LeaveCalendar(shifts: [_shift(sat.add(const Duration(hours: 6)))]);
      expect(_leave(sat, sat).workingDays(calendar), 1);
    });

    test('only rostered days count, so weekdays off are free', () {
      // Works Wednesday to Saturday, and takes the whole week off.
      final calendar = LeaveCalendar(shifts: [
        for (final day in [wed, DateTime(2026, 11, 5), fri, sat]) _shift(day.add(const Duration(hours: 6))),
      ]);
      expect(_leave(mon, sun).workingDays(calendar), 4);
    });

    test('a weekend-only worker pays nothing for weekdays in the same leave', () {
      final calendar = LeaveCalendar(shifts: [_shift(sat.add(const Duration(hours: 6))), _shift(sun.add(const Duration(hours: 6)))]);
      expect(_leave(mon, sun).workingDays(calendar), 2);
    });

    test('two shifts on one day are one leave day', () {
      final calendar = LeaveCalendar(shifts: [
        _shift(sat.add(const Duration(hours: 6)), hours: 4),
        _shift(sat.add(const Duration(hours: 13)), hours: 4),
      ]);
      expect(_leave(sat, sat).workingDays(calendar), 1);
    });

    test('an overnight shift counts on the day it starts', () {
      final calendar = LeaveCalendar(shifts: [_shift(fri.add(const Duration(hours: 22)))]);
      expect(_leave(fri, sat).workingDays(calendar), 1);
      expect(_leave(sat, sat).workingDays(calendar), 0, reason: 'no shift starts on Saturday, so Monday to Friday applies');
    });

    test('a shift stored in UTC belongs to its local day', () {
      final start = sat.add(const Duration(hours: 1));
      final fromDatabase = Shift.fromJson({
        'id': 's',
        'organization_id': 'org',
        'employee_id': _me,
        'site_location': 'Plant',
        'start_time': start.toUtc().toIso8601String(),
        'end_time': start.add(const Duration(hours: 8)).toUtc().toIso8601String(),
        'created_at': start.toUtc().toIso8601String(),
      });
      expect(_leave(sat, sat).workingDays(LeaveCalendar(shifts: [fromDatabase])), 1);
    });

    test('rostered leave across New Year counts against each year', () {
      final calendar = LeaveCalendar(shifts: [
        _shift(DateTime(2026, 12, 31, 6)), // Thursday
        _shift(DateTime(2027, 1, 2, 6)), // Saturday
        _shift(DateTime(2027, 1, 3, 6)), // Sunday
      ]);
      final r = _leave(DateTime(2026, 12, 28), DateTime(2027, 1, 3));
      expect(r.workingDaysInYear(2026, calendar), 1);
      expect(r.workingDaysInYear(2027, calendar), 2);
      expect(r.workingDays(calendar), 3);
    });
  });

  group('Public holidays', () {
    test('do not use leave for someone with no roster', () {
      final calendar = LeaveCalendar(holidays: [_holiday(wed)]);
      expect(_leave(mon, fri).workingDays(calendar), 4);
    });

    test('do not use leave on a rostered day', () {
      final calendar = LeaveCalendar(
        shifts: [_shift(sat.add(const Duration(hours: 6))), _shift(sun.add(const Duration(hours: 6)))],
        holidays: [_holiday(sun)],
      );
      expect(_leave(sat, sun).workingDays(calendar), 1);
    });

    test('on a weekend do not take off a second day', () {
      final calendar = LeaveCalendar(holidays: [_holiday(sat)]);
      expect(_leave(mon, sun).workingDays(calendar), 5);
    });

    test('a rostered holiday does not trigger the Monday to Friday fallback', () {
      // The only shift is on the holiday, so this leave uses nothing.
      final calendar = LeaveCalendar(shifts: [_shift(wed.add(const Duration(hours: 6)))], holidays: [_holiday(wed)]);
      expect(_leave(mon, fri).workingDays(calendar), 0);
    });

    test('count against neither year when they fall on New Year', () {
      final calendar = LeaveCalendar(holidays: [_holiday(DateTime(2027, 1, 1))]);
      final r = _leave(DateTime(2026, 12, 31), DateTime(2027, 1, 1));
      expect(r.workingDaysInYear(2026, calendar), 1);
      expect(r.workingDaysInYear(2027, calendar), 0);
    });

    test('a daylight saving change does not move a holiday', () {
      // Australian clocks go forward on Sunday 4 Oct 2026.
      final calendar = LeaveCalendar(holidays: [_holiday(DateTime(2026, 10, 5))]);
      expect(_leave(DateTime(2026, 10, 1), DateTime(2026, 10, 7)).workingDays(calendar), 4);
    });

    test('read the date from a database row', () {
      final h = PublicHoliday.fromJson({'id': 'h', 'organization_id': 'org', 'holiday_date': '2026-12-25', 'name': 'Christmas Day'});
      expect(h.date, DateTime(2026, 12, 25));
      expect(h.name, 'Christmas Day');
      expect(_leave(DateTime(2026, 12, 25), DateTime(2026, 12, 25)).workingDays(LeaveCalendar(holidays: [h])), 0);
    });
  });

  group('Monday to Friday fallback', () {
    test('applies when the employee has no roster at all', () {
      expect(_leave(mon, sun).workingDays(LeaveCalendar()), 5);
    });

    test('applies when their shifts are all outside the leave', () {
      final calendar = LeaveCalendar(shifts: [_shift(DateTime(2026, 11, 14, 6)), _shift(DateTime(2026, 10, 31, 6))]);
      expect(_leave(mon, sun).workingDays(calendar), 5);
    });

    test('ignores other employees\' shifts', () {
      final calendar = LeaveCalendar(shifts: [_shift(sat.add(const Duration(hours: 6)), employeeId: 'someone-else')]);
      expect(_leave(mon, sun).workingDays(calendar), 5);
    });
  });

  group('Dates to load shifts for', () {
    test('cover every request', () {
      expect(leaveDateSpan([_leave(wed, fri), _leave(mon, mon), _leave(sat, sun)]), (mon, sun));
      expect(leaveDateSpan(const []), isNull);
    });

    test('use the start date when an end date is before it', () {
      expect(leaveDateSpan([_leave(fri, mon)]), (fri, fri));
    });
  });

  group('Leave screen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await Supabase.initialize(url: 'http://127.0.0.1:9', publishableKey: 'test');
    });

    // The first Saturday of June this year, so the balance counts it.
    final year = DateTime.now().year;
    final saturday = DateTime(year, 6, 1 + (DateTime.saturday - DateTime(year, 6, 1).weekday) % 7);
    final sunday = saturday.add(const Duration(days: 1));
    final me = Employee(id: _me, organizationId: 'org', email: 'w@example.com', fullName: 'Weekend Worker', role: 'staff', createdAt: DateTime(2026));

    Future<void> pump(WidgetTester tester, Future<List<Shift>> Function() shifts, List<PublicHoliday> holidays) async {
      tester.view.physicalSize = const Size(1366, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _Auth(me)),
          leaveStateProvider.overrideWith((ref) => _Leave(ref, [_leave(saturday, saturday.add(const Duration(days: 6)))])),
          staffProvider.overrideWith((ref) => Stream.value([me])),
          rosterProvider.overrideWith((ref) => Stream.value(const [])),
          leaveShiftsProvider.overrideWith((ref) => shifts()),
          publicHolidaysProvider.overrideWith((ref) => Stream.value(holidays)),
        ],
        child: MaterialApp(theme: buildAppTheme(AppTheme.values.first), home: const LeaveScreen()),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Close realtime channels, which retry against the fake backend.
    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      unawaited(Supabase.instance.client.removeAllChannels());
      await tester.pump(const Duration(seconds: 15));
    }

    testWidgets('balance counts rostered weekend days and skips holidays', (tester) async {
      await pump(
        tester,
        () async => [_shift(saturday.add(const Duration(hours: 6))), _shift(sunday.add(const Duration(hours: 6)))],
        [_holiday(sunday)],
      );
      expect(find.text('1 of 20 used in $year'), findsOneWidget);
      expect(find.text('19 days'), findsOneWidget);
      expect(find.textContaining('1 working day'), findsOneWidget);
      expect(find.textContaining('Could not load the roster'), findsNothing);
      await finish(tester);
    });

    testWidgets('warns when the roster cannot load and falls back to Monday to Friday', (tester) async {
      await pump(tester, () async => throw Exception('offline'), const []);
      expect(find.text('5 of 20 used in $year'), findsOneWidget);
      expect(find.textContaining('Could not load the roster'), findsOneWidget);
      await finish(tester);
    });
  });
}

class _Auth extends AuthNotifier {
  _Auth(Employee me) {
    state = AuthState(initialized: true, currentUser: me);
  }
}

class _Leave extends LeaveNotifier {
  _Leave(super.ref, List<LeaveRequest> requests) {
    state = LeaveState(requests: requests);
  }
  @override
  Future<void> loadLeaveRequests({bool silent = false}) async {}
}
