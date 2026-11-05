import '../models/clock_event.dart';
import '../models/employee.dart';
import '../models/exception_record.dart';
import '../models/shift.dart';

/// A punch is matched to the closest rostered shift within this distance, the
/// same window the clock uses when it raises exceptions (see ClockService).
const shiftMatchWindow = Duration(hours: 12);

/// One employee's hours for a pay period. Hours only: no rates, tax or pay.
class TimesheetRow {
  final Employee employee;

  /// Worked time that is not overtime, with breaks deducted. Includes
  /// [unrostered] time, which has no shift to measure overtime against.
  final Duration ordinary;

  /// Worked time past the rostered shift end, with breaks deducted.
  final Duration overtime;

  /// Break time taken during the counted shifts.
  final Duration breaks;

  final Duration unrostered;

  /// Currently open compliance exceptions, whichever period they came from.
  final int openExceptions;

  /// Clock-ins with no clock-out. Their hours are not counted.
  final int missingClockOuts;

  /// Clock-outs with no clock-in. Their hours are not counted.
  final int missingClockIns;

  /// Breaks with no end time inside a counted shift. Nothing is deducted.
  final int unfinishedBreaks;

  const TimesheetRow({
    required this.employee,
    this.ordinary = Duration.zero,
    this.overtime = Duration.zero,
    this.breaks = Duration.zero,
    this.unrostered = Duration.zero,
    this.openExceptions = 0,
    this.missingClockOuts = 0,
    this.missingClockIns = 0,
    this.unfinishedBreaks = 0,
  });

  /// Plain-language problems payroll should check before relying on the hours.
  List<String> get notes {
    String count(int n, String what) => '$n $what';
    return [
      if (missingClockOuts > 0) '${count(missingClockOuts, 'clock-in')} with no clock-out (hours not counted)',
      if (missingClockIns > 0) '${count(missingClockIns, 'clock-out')} with no clock-in (hours not counted)',
      if (unfinishedBreaks > 0) '${count(unfinishedBreaks, unfinishedBreaks == 1 ? 'break' : 'breaks')} with no end time (not deducted)',
      if (unrostered > Duration.zero) '${formatHours(unrostered)}h with no rostered shift (in ordinary hours)',
    ];
  }

  bool get needsReview => openExceptions > 0 || notes.isNotEmpty;
}

/// Decimal hours to two places, the format payroll software imports.
String formatHours(Duration d) => (d.inSeconds / 3600).toStringAsFixed(2);

/// Pure hour calculations. Nothing here touches the network, so every rule is
/// unit-tested (see test/timesheet_test.dart).
class TimesheetCalculator {
  /// One row per employee in [employees], sorted by name.
  ///
  /// A shift belongs to the period its clock-in falls in ([from] inclusive,
  /// [to] exclusive), so an overnight shift is counted whole and only once.
  /// Pass punches and breaks from either side of the period too: an overnight
  /// clock-out can land after [to], and one just after [from] can belong to a
  /// shift from the previous period.
  ///
  /// Overtime follows the unapproved-overtime exception: once a clock-out is
  /// more than [allowedOvertimeMinutes] past the shift end, all the time past
  /// the shift end is overtime. Up to that allowance it stays ordinary.
  ///
  /// Every recorded break is deducted, as it is everywhere else in the app.
  static List<TimesheetRow> calculate({
    required List<Employee> employees,
    required List<ClockEvent> events,
    required List<Shift> shifts,
    required List<Map<String, dynamic>> breaks,
    required List<ExceptionRecord> exceptions,
    required int allowedOvertimeMinutes,
    required DateTime from,
    required DateTime to,
  }) {
    List<T> mine<T>(Iterable<T> items, String employeeId, String Function(T) idOf) =>
        items.where((i) => idOf(i) == employeeId).toList();

    final rows = [
      for (final employee in employees)
        _forEmployee(
          employee: employee,
          events: mine(events, employee.id, (e) => e.employeeId),
          shifts: mine(shifts, employee.id, (s) => s.employeeId),
          breaks: mine(breaks, employee.id, (b) => '${b['employee_id']}'),
          openExceptions: exceptions.where((x) => x.employeeId == employee.id && !x.isResolved && !x.isIgnored).length,
          allowance: Duration(minutes: allowedOvertimeMinutes),
          from: from,
          to: to,
        ),
    ];
    rows.sort((a, b) => a.employee.fullName.toLowerCase().compareTo(b.employee.fullName.toLowerCase()));
    return rows;
  }

  static TimesheetRow _forEmployee({
    required Employee employee,
    required List<ClockEvent> events,
    required List<Shift> shifts,
    required List<Map<String, dynamic>> breaks,
    required int openExceptions,
    required Duration allowance,
    required DateTime from,
    required DateTime to,
  }) {
    bool inPeriod(DateTime t) => !t.isBefore(from) && t.isBefore(to);

    final finishedBreaks = _mergedBreaks(breaks);
    final openBreakStarts = [
      for (final b in breaks)
        if (b['end_time'] == null) DateTime.tryParse('${b['start_time']}'),
    ].nonNulls.toList();

    var ordinary = Duration.zero, overtime = Duration.zero, breakTime = Duration.zero, unrostered = Duration.zero;
    var missingOuts = 0, missingIns = 0, unfinishedBreaks = 0;

    void countSegment(DateTime clockIn, DateTime clockOut) {
      final segmentBreaks = _overlap(finishedBreaks, clockIn, clockOut);
      final worked = clockOut.difference(clockIn) - segmentBreaks;
      breakTime += segmentBreaks;
      unfinishedBreaks += openBreakStarts.where((s) => !s.isBefore(clockIn) && s.isBefore(clockOut)).length;

      final shift = _closestShift(shifts, clockOut);
      if (shift == null) {
        unrostered += worked;
        ordinary += worked;
        return;
      }
      if (clockOut.difference(shift.endTime) <= allowance) {
        ordinary += worked;
        return;
      }
      final overtimeStart = clockIn.isAfter(shift.endTime) ? clockIn : shift.endTime;
      final extra = clockOut.difference(overtimeStart) - _overlap(finishedBreaks, overtimeStart, clockOut);
      overtime += extra;
      ordinary += worked - extra;
    }

    final punches = [...events]..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    DateTime? openIn;
    for (final punch in punches) {
      if (punch.eventType == 'clock_in') {
        if (openIn != null && inPeriod(openIn)) missingOuts++;
        openIn = punch.eventTime;
      } else if (punch.eventType == 'clock_out') {
        if (openIn == null) {
          if (inPeriod(punch.eventTime)) missingIns++;
          continue;
        }
        if (inPeriod(openIn)) countSegment(openIn, punch.eventTime);
        openIn = null;
      }
    }
    if (openIn != null && inPeriod(openIn)) missingOuts++;

    return TimesheetRow(
      employee: employee,
      ordinary: ordinary,
      overtime: overtime,
      breaks: breakTime,
      unrostered: unrostered,
      openExceptions: openExceptions,
      missingClockOuts: missingOuts,
      missingClockIns: missingIns,
      unfinishedBreaks: unfinishedBreaks,
    );
  }

  /// The shift closest to [at] within [shiftMatchWindow], or null if unrostered.
  static Shift? _closestShift(List<Shift> shifts, DateTime at) {
    Duration distance(Shift s) {
      if (at.isBefore(s.startTime)) return s.startTime.difference(at);
      if (at.isAfter(s.endTime)) return at.difference(s.endTime);
      return Duration.zero;
    }

    Shift? best;
    for (final shift in shifts) {
      final d = distance(shift);
      if (d > shiftMatchWindow) continue;
      if (best == null || d < distance(best)) best = shift;
    }
    return best;
  }

  /// Finished breaks as non-overlapping spans, in order, so that overlapping
  /// records can never be deducted twice.
  static List<(DateTime, DateTime)> _mergedBreaks(List<Map<String, dynamic>> breaks) {
    final spans = <(DateTime, DateTime)>[];
    for (final b in breaks) {
      final start = DateTime.tryParse('${b['start_time']}');
      final end = b['end_time'] == null ? null : DateTime.tryParse('${b['end_time']}');
      if (start != null && end != null && end.isAfter(start)) spans.add((start, end));
    }
    spans.sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <(DateTime, DateTime)>[];
    for (final span in spans) {
      if (merged.isNotEmpty && !span.$1.isAfter(merged.last.$2)) {
        if (span.$2.isAfter(merged.last.$2)) merged.last = (merged.last.$1, span.$2);
      } else {
        merged.add(span);
      }
    }
    return merged;
  }

  /// How much of [spans] falls between [start] and [end].
  static Duration _overlap(List<(DateTime, DateTime)> spans, DateTime start, DateTime end) {
    var total = Duration.zero;
    for (final (spanStart, spanEnd) in spans) {
      final a = spanStart.isAfter(start) ? spanStart : start;
      final b = spanEnd.isBefore(end) ? spanEnd : end;
      if (b.isAfter(a)) total += b.difference(a);
    }
    return total;
  }
}
