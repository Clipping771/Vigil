import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/leave_calendar.dart';
import '../models/leave_request.dart';
import '../models/public_holiday.dart';
import '../models/shift.dart';
import 'auth_provider.dart';
import 'leave_provider.dart';
import 'realtime_rows.dart';
import 'roster_provider.dart';

/// The organization's public holidays, kept live via Realtime.
final publicHolidaysProvider = StreamProvider<List<PublicHoliday>>((ref) {
  final orgId = ref.watch(authProvider.select((s) => s.currentUser?.organizationId));
  if (orgId == null) return Stream.value(const []);
  final clean = liveRows(ref, 'public_holidays');
  return Supabase.instance.client
      .from('public_holidays')
      .stream(primaryKey: ['id'])
      .eq('organization_id', orgId)
      .order('holiday_date', ascending: true)
      .map((rows) => clean(rows).map(PublicHoliday.fromJson).toList());
});

Future<void> addPublicHoliday({required String organizationId, required DateTime date, required String name}) async {
  await Supabase.instance.client.from('public_holidays').insert({
    'organization_id': organizationId,
    'holiday_date': '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
    'name': name.trim(),
  });
}

Future<void> removePublicHoliday(String id) async {
  await Supabase.instance.client.from('public_holidays').delete().eq('id', id);
}

/// The first and last day [requests] cover, or null if there are none.
(DateTime, DateTime)? leaveDateSpan(Iterable<LeaveRequest> requests) {
  (DateTime, DateTime)? span;
  for (final r in requests) {
    final end = r.endDate.isBefore(r.startDate) ? r.startDate : r.endDate;
    span = span == null
        ? (r.startDate, end)
        : (r.startDate.isBefore(span.$1) ? r.startDate : span.$1, end.isAfter(span.$2) ? end : span.$2);
  }
  return span;
}

/// The shifts that start during the leave requests this user can see. Balances
/// can't use [rosterProvider]: it stops at the row limit, oldest shifts first, so
/// an established organization's recent shifts would be missing.
final leaveShiftsProvider = FutureProvider<List<Shift>>((ref) async {
  final user = ref.watch(authProvider).currentUser;
  if (user == null) return const [];
  final span = ref.watch(leaveStateProvider.select((s) =>
      leaveDateSpan(user.isManager ? s.requests : s.requests.where((r) => r.employeeId == user.id))));
  if (span == null) return const [];
  ref.watch(rosterProvider); // Fetch again when the roster changes.

  final from = DateTime(span.$1.year, span.$1.month, span.$1.day).toUtc().toIso8601String();
  final to = DateTime(span.$2.year, span.$2.month, span.$2.day + 1).toUtc().toIso8601String();
  const pageSize = 1000;
  final rows = <Map<String, dynamic>>[];
  while (true) {
    var query = Supabase.instance.client
        .from('shifts')
        .select()
        .eq('organization_id', user.organizationId)
        .gte('start_time', from)
        .lt('start_time', to);
    if (!user.isManager) query = query.eq('employee_id', user.id);
    final page = await query.order('start_time').order('id').range(rows.length, rows.length + pageSize - 1);
    rows.addAll(page);
    if (page.length < pageSize) return uniqueRowsById(rows).map(Shift.fromJson).toList();
  }
});

/// Counts leave days from whatever has loaded so far. See [leaveCalendarFailedProvider].
final leaveCalendarProvider = Provider<LeaveCalendar>((ref) => LeaveCalendar(
      shifts: ref.watch(leaveShiftsProvider).valueOrNull ?? const [],
      holidays: ref.watch(publicHolidaysProvider).valueOrNull ?? const [],
    ));

/// True if the roster or holidays could not load, so counts may be too high.
final leaveCalendarFailedProvider = Provider<bool>((ref) =>
    ref.watch(leaveShiftsProvider).hasError || ref.watch(publicHolidaysProvider).hasError);
