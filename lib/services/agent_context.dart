import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/clock_event.dart';
import '../models/employee.dart';
import '../models/exception_record.dart';
import '../models/geofence_zone.dart';
import '../models/leave_request.dart';
import '../models/public_holiday.dart';
import '../models/shift.dart';
import '../providers/attendance_provider.dart' show breakLength;
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import 'exception_engine.dart' show maxBreakTimePerShift, maxBreaksPerShift, mealBreakAfter, minimumMealBreak, minimumRestBetweenShifts;

/// How far back and ahead the assistant can see.
const agentHistoryDays = 14;
const agentRosterAheadDays = 28;
const agentIssueDays = 60;

/// Short record reference shown to the model ("#1a2b3c4d").
String shortId(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// Everything Vigil AI may read for one question. Staff only get their own
/// records, matching what the app itself shows them.
class AgentData {
  final String organizationName;
  final List<Employee> employees;
  final List<Shift> shifts;
  final List<ClockEvent> events;
  final List<Map<String, dynamic>> breaks;
  final List<ExceptionRecord> exceptions;
  final List<LeaveRequest> leave;
  final List<GeofenceZone> sites;
  final List<PublicHoliday> holidays;

  const AgentData({
    required this.organizationName,
    this.employees = const [],
    this.shifts = const [],
    this.events = const [],
    this.breaks = const [],
    this.exceptions = const [],
    this.leave = const [],
    this.sites = const [],
    this.holidays = const [],
  });
}

/// Fetches a fresh snapshot of the organization's data for [me].
Future<AgentData> loadAgentData(Employee me, {DateTime? now}) async {
  final db = Supabase.instance.client;
  final clock = (now ?? DateTime.now()).toUtc();
  final org = me.organizationId;
  final mineOnly = !me.isManager;
  final historyFrom = clock.subtract(const Duration(days: agentHistoryDays)).toIso8601String();
  final issuesFrom = clock.subtract(const Duration(days: agentIssueDays)).toIso8601String();
  final rosterTo = clock.add(const Duration(days: agentRosterAheadDays)).toIso8601String();

  Future<List<Map<String, dynamic>>> rows(PostgrestTransformBuilder<List<Map<String, dynamic>>> q) async {
    try {
      return await q;
    } catch (_) {
      return const []; // One unavailable table should not silence the assistant.
    }
  }

  PostgrestFilterBuilder<List<Map<String, dynamic>>> scoped(String table) {
    final q = db.from(table).select().eq('organization_id', org);
    return mineOnly ? q.eq('employee_id', me.id) : q;
  }

  final results = await Future.wait([
    rows(db.from('organizations').select('name').eq('id', org).limit(1)),
    rows(db.from('employees').select().eq('organization_id', org).order('full_name')),
    rows(scoped('shifts').gte('end_time', historyFrom).lt('start_time', rosterTo).order('start_time').limit(800)),
    rows(scoped('clock_events').gte('event_time', historyFrom).order('event_time').limit(4000)),
    rows(scoped('breaks').gte('start_time', historyFrom).order('start_time').limit(4000)),
    rows(scoped('exception_records').or('status.eq.pending,created_at.gte.$issuesFrom').order('created_at', ascending: false).limit(300)),
    rows(scoped('leave_requests').or('status.eq.pending,end_date.gte.${issuesFrom.substring(0, 10)}').order('start_date').limit(300)),
    rows(db.from('geofence_zones').select().eq('organization_id', org).order('name')),
    rows(db.from('public_holidays').select().eq('organization_id', org).order('holiday_date')),
  ]);

  final employees = results[1].map(Employee.fromJson).toList();
  return AgentData(
    organizationName: results[0].isEmpty ? 'your organization' : (results[0].first['name'] ?? 'your organization').toString(),
    employees: mineOnly ? employees.where((e) => e.id == me.id).toList() : employees,
    shifts: results[2].map(Shift.fromJson).toList(),
    events: results[3].map(ClockEvent.fromJson).toList(),
    breaks: results[4],
    exceptions: results[5].map(ExceptionRecord.fromJson).toList(),
    leave: results[6].map(LeaveRequest.fromJson).toList(),
    sites: results[7].map(GeofenceZone.fromJson).toList(),
    holidays: results[8].map(PublicHoliday.fromJson).toList(),
  );
}

/// Renders [data] as compact text for the model's system prompt.
String formatAgentContext({
  required Employee me,
  required AgentData data,
  required AppSettings settings,
  required DateTime now,
}) {
  final local = now.toLocal();
  final day = DateFormat('EEE d MMM yyyy');
  final hm = DateFormat('HH:mm');
  String when(DateTime t) => '${day.format(t.toLocal())} ${hm.format(t.toLocal())}';
  String dur(Duration d) {
    final m = d.inMinutes;
    return m < 60 ? '${m}m' : '${m ~/ 60}h${(m % 60).toString().padLeft(2, '0')}m';
  }

  final names = {for (final e in data.employees) e.id: e.fullName};
  String who(String id, [String? fallback]) => names[id] ?? fallback ?? 'unknown employee';
  final b = StringBuffer();

  void section(String title, Iterable<String> lines, {int cap = 400, String empty = 'none'}) {
    final all = lines.toList();
    b.writeln('\n## $title${all.length > cap ? ' (first $cap of ${all.length})' : ''}');
    if (all.isEmpty) b.writeln(empty);
    for (final l in all.take(cap)) {
      b.writeln(l);
    }
  }

  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  b.writeln('Now: ${DateFormat('EEEE d MMMM yyyy, HH:mm').format(local)} '
      '(${local.timeZoneName}, UTC$sign${offset.inHours.abs().toString().padLeft(2, '0')}:${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}). All times below are local.');
  b.writeln('Organization: ${data.organizationName}');
  b.writeln('Signed-in user: ${me.fullName} | role ${me.role} | site ${me.siteLocation ?? '-'}');
  b.writeln(me.isManager
      ? 'Scope: the whole organization.'
      : 'Scope: only this user\'s own records. You do not have other employees\' data.');

  section('Compliance rules', [
    'Late clock-in grace period: ${settings.allowedLateMinutes} min',
    'Overtime allowed after shift end: ${settings.allowedOvertimeMinutes} min',
    'Meal break: at least ${minimumMealBreak.inMinutes} min once more than ${mealBreakAfter.inHours}h is worked (Fair Work)',
    'Rest between shifts: at least ${minimumRestBetweenShifts.inHours}h',
    'Breaks: at most $maxBreaksPerShift breaks and ${maxBreakTimePerShift.inMinutes} min of breaks per shift',
  ]);

  section('Work sites (geofences)', [
    for (final s in data.sites) '${s.name} | radius ${s.radiusMeters.round()} m | ${s.latitude.toStringAsFixed(5)}, ${s.longitude.toStringAsFixed(5)}',
  ]);

  if (me.isManager) {
    section('Staff (#id | name | role | site | email)', [
      for (final e in data.employees) '#${shortId(e.id)} | ${e.fullName} | ${e.role} | ${e.siteLocation ?? '-'} | ${e.email}',
    ]);
  }

  // ---- Attendance, rebuilt from punches and breaks.
  final byEmployee = <String, List<ClockEvent>>{};
  for (final ev in data.events) {
    byEmployee.putIfAbsent(ev.employeeId, () => []).add(ev);
  }
  final breakMinutes = <String, int>{}; // employeeId|yyyy-mm-dd -> minutes
  final onBreak = <String, DateTime>{};
  for (final br in data.breaks) {
    final start = DateTime.tryParse('${br['start_time']}');
    if (start == null) continue;
    final empId = '${br['employee_id']}';
    final end = br['end_time'] == null ? null : DateTime.tryParse('${br['end_time']}');
    if (end == null) {
      onBreak[empId] = start;
      continue;
    }
    final key = '$empId|${DateFormat('yyyy-MM-dd').format(start.toLocal())}';
    breakMinutes[key] = (breakMinutes[key] ?? 0) + breakLength(br).inMinutes;
  }

  final liveLines = <String>[];
  final liveIds = <String>{};
  final dayLines = <({DateTime first, String line})>[];
  final totals = <String, Duration>{};
  for (final entry in byEmployee.entries) {
    final evs = entry.value..sort((a, b) => a.eventTime.compareTo(b.eventTime));
    final perDay = <String, ({DateTime first, DateTime? last, Duration worked, bool open, List<String> sites})>{};
    DateTime? openIn;
    for (final ev in evs) {
      final key = DateFormat('yyyy-MM-dd').format(ev.eventTime.toLocal());
      final d = perDay[key] ?? (first: ev.eventTime, last: null, worked: Duration.zero, open: false, sites: <String>[]);
      if (ev.eventType == 'clock_in') {
        openIn = ev.eventTime;
        perDay[key] = (first: d.first, last: d.last, worked: d.worked, open: true, sites: [...d.sites, if (!ev.isGeofenced) 'outside site']);
      } else if (ev.eventType == 'clock_out' && openIn != null) {
        final inKey = DateFormat('yyyy-MM-dd').format(openIn.toLocal());
        final di = perDay[inKey]!;
        perDay[inKey] = (first: di.first, last: ev.eventTime, worked: di.worked + ev.eventTime.difference(openIn), open: false, sites: di.sites);
        openIn = null;
      }
    }
    if (openIn != null) {
      final inKey = DateFormat('yyyy-MM-dd').format(openIn.toLocal());
      final di = perDay[inKey]!;
      perDay[inKey] = (first: di.first, last: di.last, worked: di.worked + now.difference(openIn), open: true, sites: di.sites);
      final status = onBreak.containsKey(entry.key) ? 'ON BREAK since ${hm.format(onBreak[entry.key]!.toLocal())}' : 'CLOCKED IN';
      liveIds.add(entry.key);
      liveLines.add('${who(entry.key)} | $status | clocked in ${when(openIn)}');
    }
    for (final p in perDay.entries) {
      final brk = Duration(minutes: breakMinutes['${entry.key}|${p.key}'] ?? 0);
      final net = p.value.worked - brk;
      totals[entry.key] = (totals[entry.key] ?? Duration.zero) + net;
      dayLines.add((
        first: p.value.first,
        line: '${day.format(p.value.first.toLocal())} | ${who(entry.key)} | in ${hm.format(p.value.first.toLocal())} | '
            'out ${p.value.open ? 'still clocked in' : (p.value.last == null ? '-' : hm.format(p.value.last!.toLocal()))} | '
            'breaks ${dur(brk)} | worked ${dur(net)}${p.value.sites.isEmpty ? '' : ' | clocked in outside a work site'}',
      ));
    }
  }

  section('Live right now', liveLines, empty: 'Nobody is clocked in.');
  if (me.isManager) {
    final out = data.employees.where((e) => !liveIds.contains(e.id)).map((e) => e.fullName).toList()..sort();
    b.writeln('Not clocked in: ${out.isEmpty ? 'nobody' : out.join(', ')}');
  }

  dayLines.sort((a, b) => b.first.compareTo(a.first));
  section('Attendance, last $agentHistoryDays days (newest first; worked = clocked time minus breaks)', dayLines.map((d) => d.line), cap: 500);
  section('Hours worked per person, last $agentHistoryDays days', [
    for (final e in (totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) '${who(e.key)} | ${dur(e.value)}',
  ]);

  final today = DateTime(local.year, local.month, local.day);
  String dayTag(DateTime t) {
    final d = DateTime(t.toLocal().year, t.toLocal().month, t.toLocal().day).difference(today).inDays;
    return d == 0 ? ' (TODAY)' : d == 1 ? ' (tomorrow)' : d == -1 ? ' (yesterday)' : '';
  }

  final shifts = [...data.shifts]..sort((a, b) => a.startTime.compareTo(b.startTime));
  section('Rostered shifts, $agentHistoryDays days back to $agentRosterAheadDays days ahead (#id | date | time | employee | site)', [
    for (final s in shifts)
      '#${shortId(s.id)} | ${day.format(s.startTime.toLocal())}${dayTag(s.startTime)} | ${hm.format(s.startTime.toLocal())}-${hm.format(s.endTime.toLocal())} '
          '(${dur(s.endTime.difference(s.startTime))}) | ${who(s.employeeId)} | ${s.siteLocation}'
          '${s.startTime.isBefore(now) && s.endTime.isAfter(now) ? ' | IN PROGRESS' : ''}',
  ], cap: 600);

  final issues = [...data.exceptions]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  final pending = issues.where((e) => e.status == 'pending').toList();
  String issue(ExceptionRecord e) => '#${shortId(e.id)} | ${when(e.createdAt)} | ${who(e.employeeId, e.employeeName)} | ${e.typeTitle} | ${e.severity} | ${e.status}'
      '${e.reviewedById == null ? '' : ' by ${who(e.reviewedById!, e.reviewedByName)}'}'
      ' | ${e.description ?? ''}${(e.resolutionNote ?? '').isEmpty ? '' : ' | note: ${e.resolutionNote}'}';
  section('Open compliance issues (pending review)', pending.map(issue), cap: 150);
  section('Reviewed issues, last $agentIssueDays days', issues.where((e) => e.status != 'pending').map(issue), cap: 150);

  section('Leave requests (#id | employee | type | dates | days | status | reason)', [
    for (final l in data.leave)
      '#${shortId(l.id)} | ${who(l.employeeId, l.employeeName)} | ${l.leaveType} | ${day.format(l.startDate)} to ${day.format(l.endDate)} | '
          '${l.endDate.difference(l.startDate).inDays + 1} | ${l.status} | ${l.reason ?? '-'}',
  ]);

  return b.toString();
}
