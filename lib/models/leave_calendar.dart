import 'public_holiday.dart';
import 'shift.dart';

/// What leave day counting needs to know: who is rostered when, and which dates
/// are public holidays. An empty calendar counts Monday to Friday.
class LeaveCalendar {
  final Map<String, Set<DateTime>> _rosteredDays = {};
  final Set<DateTime> _holidays;

  /// A shift belongs to the local day it starts on, so an overnight shift is one
  /// leave day and two shifts on one day are also one.
  LeaveCalendar({Iterable<Shift> shifts = const [], Iterable<PublicHoliday> holidays = const []})
      : _holidays = {for (final h in holidays) dayOf(h.date)} {
    for (final s in shifts) {
      (_rosteredDays[s.employeeId] ??= {}).add(dayOf(s.startTime.toLocal()));
    }
  }

  /// [time]'s calendar date in UTC, because a daylight saving change makes a
  /// local day 23 hours.
  static DateTime dayOf(DateTime time) => DateTime.utc(time.year, time.month, time.day);

  /// Which of [days] use up leave for [employeeId]. If the employee has a shift
  /// on any of them, only their rostered days count. Otherwise Monday to Friday
  /// count. Public holidays never count.
  Iterable<DateTime> leaveDays(String employeeId, List<DateTime> days) {
    final rostered = _rosteredDays[employeeId] ?? const <DateTime>{};
    final hasRoster = days.any(rostered.contains);
    return days.where((day) =>
        !_holidays.contains(day) && (hasRoster ? rostered.contains(day) : day.weekday <= DateTime.friday));
  }
}
