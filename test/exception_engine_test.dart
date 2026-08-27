import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/models/shift.dart';
import 'package:vigil/services/exception_engine.dart';

void main() {
  group('ExceptionEngine Tests', () {
    final now = DateTime.now();

    test('Should return null for a normal clock out on time', () {
      final shift = Shift(
        id: 'shift-1',
        organizationId: 'org-1',
        employeeId: 'emp-1',
        siteLocation: 'Oakleigh',
        startTime: now.subtract(const Duration(hours: 4)),
        endTime: now,
        createdAt: now,
      );

      final event = ClockEvent(
        id: 'evt-1',
        organizationId: 'org-1',
        employeeId: 'emp-1',
        eventType: 'clock_out',
        eventTime: now,
        createdAt: now,
      );

      final exception = ExceptionEngine.processClockEvent(
        event: event,
        scheduledShift: shift,
        allowedLateMinutes: 15,
        allowedOvertimeMinutes: 30,
        organizationId: 'org-1',
      );
      expect(exception, isNull, reason: 'A normal clock out should not trigger an exception.');
    });

    test('Should flag roster_breach when clocking in without a shift', () {
      final event = ClockEvent(
        id: 'evt-2',
        organizationId: 'org-1',
        employeeId: 'emp-1',
        eventType: 'clock_in',
        eventTime: now,
        createdAt: now,
      );

      final exception = ExceptionEngine.processClockEvent(
        event: event,
        scheduledShift: null,
        allowedLateMinutes: 15,
        allowedOvertimeMinutes: 30,
        organizationId: 'org-1',
      );
      
      expect(exception, isNotNull);
      expect(exception!.exceptionType, 'roster_breach');
      expect(exception.severity, 'high');
    });

    test('Should flag excessive_overtime when clocking out 45 mins late', () {
      final shiftEnd = now.subtract(const Duration(minutes: 45));
      final shift = Shift(
        id: 'shift-2',
        organizationId: 'org-1',
        employeeId: 'emp-2',
        siteLocation: 'Oakleigh',
        startTime: shiftEnd.subtract(const Duration(hours: 8)),
        endTime: shiftEnd,
        createdAt: now,
      );

      final event = ClockEvent(
        id: 'evt-3',
        organizationId: 'org-1',
        employeeId: 'emp-2',
        eventType: 'clock_out',
        eventTime: now, // 45 mins after shiftEnd
        createdAt: now,
      );

      final exception = ExceptionEngine.processClockEvent(
        event: event,
        scheduledShift: shift,
        allowedLateMinutes: 15,
        allowedOvertimeMinutes: 30,
        organizationId: 'org-1',
      );
      
      expect(exception, isNotNull);
      expect(exception!.exceptionType, 'excessive_overtime');
      expect(exception.severity, 'medium');
    });

    test('Should flag missed_clock_in when shift started 30 mins ago and no event exists', () {
      final shiftStart = now.subtract(const Duration(minutes: 30));
      final shift = Shift(
        id: 'shift-3',
        organizationId: 'org-1',
        employeeId: 'emp-3',
        siteLocation: 'Oakleigh',
        startTime: shiftStart,
        endTime: shiftStart.add(const Duration(hours: 8)),
        createdAt: now,
      );

      // Empty events list means no clock in
      final exceptions = ExceptionEngine.detectMissedClockIns(
        activeShifts: [shift], 
        todayEvents: [],
        allowedLateMinutes: 15,
        organizationId: 'org-1',
      );

      expect(exceptions.length, 1);
      expect(exceptions.first.exceptionType, 'missed_clock_in');
      expect(exceptions.first.employeeId, 'emp-3');
      expect(exceptions.first.severity, 'high');
    });
  });
}
