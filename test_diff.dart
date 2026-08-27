import 'dart:convert';
import 'package:vigil/models/shift.dart';
import 'package:vigil/models/clock_event.dart';
import 'package:vigil/models/leave_request.dart';
import 'package:vigil/services/exception_engine.dart';

void main() {
  final orgId = 'org-1';
  final empId = 'emp-1';
  final now = DateTime.parse('2026-08-22T10:00:00Z');
  
  final shifts = [
    Shift(
      id: 'shift-1',
      organizationId: orgId,
      employeeId: empId,
      siteLocation: 'Site A',
      startTime: now.subtract(const Duration(hours: 24)),
      endTime: now.subtract(const Duration(hours: 16)), // Ended 16 hours ago
      createdAt: now,
    ),
    Shift(
      id: 'shift-2',
      organizationId: orgId,
      employeeId: empId,
      siteLocation: 'Site A',
      startTime: now.subtract(const Duration(hours: 10)), // Started 10 hours ago -> gap is only 6 hours!
      endTime: now.subtract(const Duration(hours: 2)),
      createdAt: now,
    )
  ];
  
  final events = [
    ClockEvent(
      id: 'event-1',
      organizationId: orgId,
      employeeId: empId,
      eventType: 'clock_out',
      eventTime: now.subtract(const Duration(hours: 2)),
      createdAt: now,
    )
  ];
  
  final leaves = <LeaveRequest>[];

  // Process clock out
  final ex1 = ExceptionEngine.processClockEvent(
    event: events.first,
    scheduledShift: shifts.last,
    allowedLateMinutes: 15,
    allowedOvertimeMinutes: 15,
    organizationId: orgId,
  );
  
  print('--- Real-time Exceptions ---');
  if (ex1 != null) {
    print('${ex1.exceptionType}: ${ex1.description}');
  } else {
    print('None');
  }

  // Process schedule
  final scheduleEx = ExceptionEngine.detectRestBreaches(
    upcomingShifts: [shifts.last],
    pastShifts: [shifts.first],
    organizationId: orgId,
  );

  print('\n--- Scheduled Shift Exceptions (Fair Work Act) ---');
  if (scheduleEx.isEmpty) {
    print('None');
  }
  for (var ex in scheduleEx) {
    print('${ex.exceptionType}: ${ex.description}');
  }
}
