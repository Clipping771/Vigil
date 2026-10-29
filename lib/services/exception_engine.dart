import 'package:intl/intl.dart';
import '../models/clock_event.dart';
import '../models/exception_record.dart';
import '../models/leave_request.dart';
import '../models/shift.dart';

/// Fair Work: an unpaid meal break of at least 30 minutes is due once an
/// employee works more than 5 hours.
const mealBreakAfter = Duration(hours: 5);
const minimumMealBreak = Duration(minutes: 30);

/// Minimum rest between consecutive shifts.
const minimumRestBetweenShifts = Duration(hours: 10);

/// Pure compliance rules. Nothing here touches the network, so every rule is
/// unit-tested (see test/exception_engine_test.dart).
class ExceptionEngine {
  static final _time = DateFormat('h:mm a');

  static String _duration(Duration d) {
    final m = d.inMinutes.abs();
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  static ExceptionRecord _record({
    required String organizationId,
    required String employeeId,
    required String type,
    required String severity,
    required String description,
    String? shiftId,
  }) =>
      ExceptionRecord(
        id: '',
        organizationId: organizationId,
        employeeId: employeeId,
        exceptionType: type,
        severity: severity,
        shiftId: shiftId,
        status: 'pending',
        description: description,
        createdAt: DateTime.now(),
      );

  /// Every rule that applies to a single punch.
  ///
  /// For a clock-out, [clockInTime] is when the open segment started and
  /// [breakTaken] is the break time recorded inside that segment.
  static List<ExceptionRecord> evaluatePunch({
    required ClockEvent event,
    required Shift? shift,
    required int graceMinutes,
    required int overtimeMinutes,
    required String organizationId,
    DateTime? clockInTime,
    Duration breakTaken = Duration.zero,
  }) {
    final out = <ExceptionRecord>[];
    final at = event.eventTime;
    final grace = Duration(minutes: graceMinutes);

    if (event.eventType == 'clock_in') {
      if (shift == null) {
        out.add(_record(
          organizationId: organizationId,
          employeeId: event.employeeId,
          type: 'roster_breach',
          severity: 'high',
          description: 'Clocked in at ${_time.format(at.toLocal())} with no shift rostered.',
        ));
        return out;
      }

      final late = at.difference(shift.startTime);
      if (late > grace) {
        out.add(_record(
          organizationId: organizationId,
          employeeId: event.employeeId,
          shiftId: shift.id,
          type: 'late_clock_in',
          severity: late >= const Duration(hours: 1) ? 'high' : 'medium',
          description: 'Clocked in ${_duration(late)} late — shift started at ${_time.format(shift.startTime.toLocal())}, '
              'clocked in at ${_time.format(at.toLocal())} (grace period $graceMinutes min).',
        ));
      }
      return out;
    }

    // ---- clock_out
    final start = clockInTime;
    final worked = start == null ? null : at.difference(start) - breakTaken;

    if (shift != null) {
      final early = shift.endTime.difference(at);
      if (early > grace) {
        final rostered = shift.endTime.difference(shift.startTime);
        final workedShare = worked == null || rostered.inMinutes == 0 ? 1.0 : worked.inMinutes / rostered.inMinutes;
        out.add(_record(
          organizationId: organizationId,
          employeeId: event.employeeId,
          shiftId: shift.id,
          type: 'early_departure',
          severity: workedShare < 0.5 ? 'high' : 'medium',
          description: 'Left ${_duration(early)} before the shift ended at ${_time.format(shift.endTime.toLocal())}'
              '${worked == null ? '' : ' — worked ${_duration(worked)} of a ${_duration(rostered)} shift'}.',
        ));
      }

      final overtime = at.difference(shift.endTime);
      if (overtime > Duration(minutes: overtimeMinutes)) {
        out.add(_record(
          organizationId: organizationId,
          employeeId: event.employeeId,
          shiftId: shift.id,
          type: 'excessive_overtime',
          severity: overtime >= const Duration(hours: 2) ? 'high' : 'medium',
          description: 'Clocked out ${_duration(overtime)} after the shift ended at ${_time.format(shift.endTime.toLocal())} '
              '(allowed $overtimeMinutes min).',
        ));
      }
    }

    // Break rule uses time actually worked, not the rostered length.
    if (worked != null && worked > mealBreakAfter && breakTaken < minimumMealBreak) {
      out.add(_record(
        organizationId: organizationId,
        employeeId: event.employeeId,
        shiftId: shift?.id,
        type: 'fair_work_compliance_breach',
        severity: 'high',
        description: 'Worked ${_duration(worked)} with only ${_duration(breakTaken)} of breaks — '
            'a ${minimumMealBreak.inMinutes}-minute meal break is required after ${mealBreakAfter.inHours} hours.',
      ));
    }
    return out;
  }

  /// Shifts with no clock-in after the grace period (no-shows), and shifts
  /// that ended while the employee is still clocked in (forgot to clock out).
  static List<ExceptionRecord> detectMissedPunches({
    required List<Shift> shifts,
    required List<ClockEvent> events,
    required int graceMinutes,
    required int overtimeMinutes,
    required String organizationId,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final out = <ExceptionRecord>[];

    for (final shift in shifts) {
      final windowStart = shift.startTime.subtract(const Duration(hours: 2));
      final mine = events
          .where((e) => e.employeeId == shift.employeeId && !e.eventTime.isBefore(windowStart))
          .toList()
        ..sort((a, b) => a.eventTime.compareTo(b.eventTime));
      final clockedIn = mine.any((e) => e.eventType == 'clock_in' && e.eventTime.isBefore(shift.endTime));

      if (!clockedIn) {
        if (clock.difference(shift.startTime) > Duration(minutes: graceMinutes)) {
          final ended = clock.isAfter(shift.endTime);
          out.add(_record(
            organizationId: organizationId,
            employeeId: shift.employeeId,
            shiftId: shift.id,
            type: 'missed_clock_in',
            severity: 'high',
            description: ended
                ? 'No-show: did not clock in for the ${_time.format(shift.startTime.toLocal())}–${_time.format(shift.endTime.toLocal())} shift at ${shift.siteLocation}.'
                : 'Not clocked in ${_duration(clock.difference(shift.startTime))} after the shift started at ${_time.format(shift.startTime.toLocal())}.',
          ));
        }
        continue;
      }

      // Still clocked in long after the shift ended?
      final last = mine.isEmpty ? null : mine.last;
      final stillIn = last != null && last.eventType == 'clock_in';
      final cutoff = shift.endTime.add(Duration(minutes: overtimeMinutes + 60));
      if (stillIn && clock.isAfter(cutoff)) {
        out.add(_record(
          organizationId: organizationId,
          employeeId: shift.employeeId,
          shiftId: shift.id,
          type: 'missed_clock_out',
          severity: 'medium',
          description: 'Still clocked in ${_duration(clock.difference(shift.endTime))} after the shift ended at '
              '${_time.format(shift.endTime.toLocal())} — likely forgot to clock out.',
        ));
      }
    }
    return out;
  }

  /// Rostered shifts that fall inside approved leave.
  static List<ExceptionRecord> detectLeaveConflicts({
    required List<Shift> upcomingShifts,
    required List<LeaveRequest> approvedLeave,
    required String organizationId,
  }) {
    final out = <ExceptionRecord>[];
    for (final shift in upcomingShifts) {
      for (final leave in approvedLeave) {
        if (shift.employeeId != leave.employeeId || leave.status != 'approved') continue;
        // Leave dates are whole days: the leave covers through the end of endDate.
        final leaveEnd = DateTime(leave.endDate.year, leave.endDate.month, leave.endDate.day).add(const Duration(days: 1));
        if (shift.startTime.isBefore(leaveEnd) && shift.endTime.isAfter(leave.startDate)) {
          out.add(_record(
            organizationId: organizationId,
            employeeId: shift.employeeId,
            shiftId: shift.id,
            type: 'leave_roster_conflict',
            severity: 'high',
            description: 'Rostered ${_time.format(shift.startTime.toLocal())}–${_time.format(shift.endTime.toLocal())} '
                'during approved ${leave.leaveType} leave.',
          ));
          break;
        }
      }
    }
    return out;
  }

  /// Consecutive shifts for the same employee with less than 10 hours rest.
  /// Only shifts in [upcomingShifts] are flagged.
  static List<ExceptionRecord> detectRestBreaches({
    required List<Shift> upcomingShifts,
    required List<Shift> pastShifts,
    required String organizationId,
  }) {
    final out = <ExceptionRecord>[];
    final upcomingIds = upcomingShifts.map((s) => s.id).toSet();
    final byEmployee = <String, Map<String, Shift>>{};
    for (final shift in [...pastShifts, ...upcomingShifts]) {
      byEmployee.putIfAbsent(shift.employeeId, () => {})[shift.id] = shift;
    }

    for (final shiftsById in byEmployee.values) {
      final shifts = shiftsById.values.toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
      for (int i = 1; i < shifts.length; i++) {
        final prev = shifts[i - 1], curr = shifts[i];
        if (!upcomingIds.contains(curr.id)) continue;
        final rest = curr.startTime.difference(prev.endTime);
        if (!rest.isNegative && rest < minimumRestBetweenShifts) {
          out.add(_record(
            organizationId: organizationId,
            employeeId: curr.employeeId,
            shiftId: curr.id,
            type: 'fair_work_compliance_breach',
            severity: 'high',
            description: 'Only ${_duration(rest)} rest between shifts — at least ${minimumRestBetweenShifts.inHours} hours is required.',
          ));
        }
      }
    }
    return out;
  }
}
