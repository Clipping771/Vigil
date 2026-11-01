import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/models/exception_record.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/providers/attendance_provider.dart';
import 'package:vigil/services/exception_engine.dart';

final _day = DateTime(2026, 10, 29);
DateTime _at(int h, [int m = 0]) => _day.add(Duration(hours: h, minutes: m));

Shift _shift({int startH = 8, int startM = 45, int endH = 17, int endM = 0, String id = 's1', String emp = 'e1'}) => Shift(
      id: id,
      organizationId: 'org',
      employeeId: emp,
      siteLocation: 'Adelaide CBD',
      startTime: _at(startH, startM),
      endTime: _at(endH, endM),
      createdAt: _day,
    );

ClockEvent _punch(String type, DateTime at, {String emp = 'e1'}) => ClockEvent(
      id: '$type-$at',
      organizationId: 'org',
      employeeId: emp,
      eventType: type,
      eventTime: at,
      createdAt: at,
    );

List<ExceptionRecord> _eval(String type, DateTime at, {Shift? shift, DateTime? clockIn, Duration breaks = Duration.zero, bool noShift = false}) =>
    ExceptionEngine.evaluatePunch(
      event: _punch(type, at),
      shift: noShift ? null : (shift ?? _shift()),
      graceMinutes: 15,
      overtimeMinutes: 30,
      organizationId: 'org',
      clockInTime: clockIn,
      breakTaken: breaks,
    );

Iterable<String> _types(List<ExceptionRecord> r) => r.map((e) => e.exceptionType);

void main() {
  group('Reported scenario: shift 8:45, clocked in 9:45, out 9:50', () {
    test('clock-in one hour late is flagged as a high-severity late clock-in', () {
      final r = _eval('clock_in', _at(9, 45));
      expect(_types(r), ['late_clock_in']);
      expect(r.single.severity, 'high');
      expect(r.single.description, contains('1h late'));
    });

    test('clocking out 5 minutes later is flagged as leaving early — and not as a break breach', () {
      final r = _eval('clock_out', _at(9, 50), clockIn: _at(9, 45));
      expect(_types(r), ['early_departure']);
      expect(r.single.severity, 'high', reason: 'worked well under half the shift');
      expect(r.single.description, contains('worked 5 min'));
    });
  });

  group('Clock-in', () {
    test('within the grace period raises nothing', () {
      expect(_eval('clock_in', _at(8, 55)), isEmpty);
    });

    test('slightly late (over grace, under an hour) is medium severity', () {
      final r = _eval('clock_in', _at(9, 10));
      expect(_types(r), ['late_clock_in']);
      expect(r.single.severity, 'medium');
    });

    test('with no rostered shift is a roster breach', () {
      expect(_types(_eval('clock_in', _at(10), noShift: true)), ['roster_breach']);
    });
  });

  group('Clock-out', () {
    test('a normal full shift with a meal break raises nothing', () {
      final r = _eval('clock_out', _at(17, 5), clockIn: _at(8, 40), breaks: const Duration(minutes: 30));
      expect(r, isEmpty);
    });

    test('working over 5 hours without a 30-minute break is a Fair Work breach', () {
      final r = _eval('clock_out', _at(17), clockIn: _at(8, 45), breaks: const Duration(minutes: 10));
      expect(_types(r), ['fair_work_compliance_breach']);
    });

    test('a short shift never triggers the break rule, even if rostered long', () {
      final r = _eval('clock_out', _at(17), shift: _shift(startH: 13, startM: 0), clockIn: _at(13));
      expect(_types(r), isNot(contains('fair_work_compliance_breach')));
    });

    test('staying 45 minutes past the shift end is unapproved overtime', () {
      final r = _eval('clock_out', _at(17, 45), clockIn: _at(8, 45), breaks: const Duration(minutes: 30));
      expect(_types(r), ['excessive_overtime']);
    });

    test('leaving early and missing the break are both reported', () {
      final r = _eval('clock_out', _at(15), clockIn: _at(8, 45));
      expect(_types(r), containsAll(['early_departure', 'fair_work_compliance_breach']));
      expect(r.firstWhere((e) => e.exceptionType == 'early_departure').severity, 'medium');
    });
  });

  group('Missed punches (server/scan)', () {
    List<ExceptionRecord> scan(List<ClockEvent> events, DateTime now) => ExceptionEngine.detectMissedPunches(
          shifts: [_shift()],
          events: events,
          graceMinutes: 15,
          overtimeMinutes: 30,
          organizationId: 'org',
          now: now,
        );

    test('not clocked in 30 minutes after start is a missed clock-in', () {
      final r = scan([], _at(9, 15));
      expect(_types(r), ['missed_clock_in']);
      expect(r.single.description, contains('Not clocked in'));
    });

    test('inside the grace period nothing is raised yet', () {
      expect(scan([], _at(8, 55)), isEmpty);
    });

    test('after the shift ends with no punch it is a no-show', () {
      expect(scan([], _at(18)).single.description, startsWith('No-show'));
    });

    test('still clocked in well after the shift ended is a missed clock-out', () {
      final r = scan([_punch('clock_in', _at(8, 40))], _at(19));
      expect(_types(r), ['missed_clock_out']);
    });

    test('a completed shift raises nothing', () {
      expect(scan([_punch('clock_in', _at(8, 40)), _punch('clock_out', _at(17, 2))], _at(19)), isEmpty);
    });
  });

  group('Breaks', () {
    ExceptionRecord? check(List<int> minutes) => ExceptionEngine.evaluateBreaks(
        breaks: [for (final m in minutes) Duration(minutes: m)], clockInTime: _at(9), employeeId: 'e1', organizationId: 'org');

    test('normal breaks raise nothing', () {
      expect(check([]), isNull);
      expect(check([10, 30, 10]), isNull); // 3 breaks, 50 min
    });

    test('too many breaks are flagged', () {
      final r = check([5, 5, 5, 5])!;
      expect(r.exceptionType, 'excessive_breaks');
      expect(r.severity, 'medium');
      expect(r.description, contains('Took 4 breaks (20 min in total) since clocking in at 9:00 AM'));
    });

    test('too much break time is flagged, more than 90 min is high', () {
      expect(check([40, 25])!.severity, 'medium');
      expect(check([100])!.severity, 'high');
    });

    test('break length uses exact timestamps, not rounded minutes', () {
      final b = {
        'start_time': DateTime.utc(2026, 11, 2, 1, 0, 0).toIso8601String(),
        'end_time': DateTime.utc(2026, 11, 2, 1, 0, 5).toIso8601String(),
        'duration_minutes': 1,
      };
      expect(breakLength(b), const Duration(seconds: 5));
      expect(breakLength({'start_time': b['start_time'], 'end_time': null}), Duration.zero);
    });

    test('a short break does not reset the time worked', () {
      // Clocked in 30 s ago and took a 5 s break: about 25 s worked, not zero.
      final s = AttendanceState(
        status: ShiftStatus.clockedIn,
        lastClockIn: DateTime.now().subtract(const Duration(seconds: 30)),
        currentSegmentBreak: const Duration(seconds: 5),
      );
      expect(s.currentLiveDuration.inSeconds, inInclusiveRange(24, 26));
    });
  });
}
