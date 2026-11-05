import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/employee.dart';
import '../models/exception_record.dart';
import '../models/leave_request.dart';
import '../models/shift.dart';
import '../providers/auth_provider.dart';
import '../providers/exception_provider.dart';
import '../providers/leave_provider.dart';
import '../providers/roster_provider.dart';
import 'agent_context.dart';

const leaveTypes = {'annual', 'sick', 'unpaid', 'maternity', 'paternity', 'compassionate', 'other'};

enum ProposalStatus { pending, running, done, failed, cancelled }

/// A change Vigil AI suggested. Nothing happens until a person approves it.
/// [summary] is written by the app from the real record, not by the model.
class AgentProposal {
  final String type;
  final Map<String, dynamic> args;
  final String summary;
  final ProposalStatus status;
  final String? result;

  const AgentProposal({required this.type, required this.args, required this.summary, this.status = ProposalStatus.pending, this.result});

  AgentProposal copyWith({ProposalStatus? status, String? result}) =>
      AgentProposal(type: type, args: args, summary: summary, status: status ?? this.status, result: result ?? this.result);

  /// How the proposal is described back to the model in later turns.
  String get historyNote => switch (status) {
        ProposalStatus.pending || ProposalStatus.running => '[Proposed, awaiting approval: $summary]',
        ProposalStatus.done => '[User approved and it was done: $summary]',
        ProposalStatus.failed => '[User approved but it failed: $summary — ${result ?? ''}]',
        ProposalStatus.cancelled => '[User declined: $summary]',
      };
}

/// The changes [me] may ask Vigil AI to prepare, as described to the model.
List<String> proposalTypesFor(Employee me) => [
      if (me.isManager) ...[
        'approve_leave {"id"} / decline_leave {"id"}: a pending leave request',
        'resolve_issue {"id","note"?} / acknowledge_issue {"id"} / dismiss_issue {"id","reason"?}: a pending compliance issue',
        'add_shift {"employee_id","start":"YYYY-MM-DDTHH:MM","end":"YYYY-MM-DDTHH:MM","site"}: local times; an end before the start means the next day',
        'remove_shift {"id"}',
        'run_compliance_scan {}: check today\'s rosters and punches for new issues',
      ],
      'request_leave {${me.isManager ? '"employee_id"?, ' : ''}"leave_type","start_date":"YYYY-MM-DD","end_date":"YYYY-MM-DD","reason"?}: leave_type is one of ${leaveTypes.join(', ')}',
      'withdraw_leave {"id"}: a pending leave request${me.isManager ? '' : ' of the user\'s own'}',
    ];

/// Turns the model's raw proposals into reviewable cards. Anything that does
/// not match a real record or the user's permissions is reported in `rejected`.
({List<AgentProposal> proposals, List<String> rejected}) resolveProposals(
  List<Map<String, dynamic>> raw,
  Employee me,
  AgentData data,
) {
  final day = DateFormat('EEE d MMM yyyy');
  final hm = DateFormat('HH:mm');
  final proposals = <AgentProposal>[];
  final rejected = <String>[];

  T? find<T>(Iterable<T> items, String Function(T) idOf, Object? ref) {
    final key = '${ref ?? ''}'.replaceFirst('#', '').trim().toLowerCase();
    if (key.length < 4) return null;
    final hits = items.where((i) => idOf(i).toLowerCase().startsWith(key)).toList();
    return hits.length == 1 ? hits.first : null;
  }

  String nameOf(String id, [String? fallback]) =>
      data.employees.where((e) => e.id == id).firstOrNull?.fullName ?? fallback ?? 'an employee';
  DateTime? date(Object? v) => DateTime.tryParse('${v ?? ''}');

  for (final p in raw.take(10)) {
    final type = '${p['type'] ?? ''}';
    String? reject(String why) {
      rejected.add('$type: $why');
      return null;
    }

    void add(String summary, Map<String, dynamic> args) => proposals.add(AgentProposal(type: type, args: args, summary: summary));
    final managerOnly = const {'approve_leave', 'decline_leave', 'resolve_issue', 'acknowledge_issue', 'dismiss_issue', 'add_shift', 'remove_shift', 'run_compliance_scan'};
    if (managerOnly.contains(type) && !me.isManager) {
      reject('only managers can do this');
      continue;
    }

    switch (type) {
      case 'approve_leave' || 'decline_leave':
        final l = find<LeaveRequest>(data.leave, (l) => l.id, p['id']);
        if (l == null) {
          reject('leave request not found');
        } else if (!l.isPending) {
          reject('that leave request is already ${l.status}');
        } else if (l.employeeId == me.id && !me.isOrgAdmin) {
          reject('you cannot decide your own leave');
        } else {
          add('${type == 'approve_leave' ? 'Approve' : 'Decline'} ${l.leaveType} leave for ${nameOf(l.employeeId, l.employeeName)}: '
              '${day.format(l.startDate)} to ${day.format(l.endDate)} (${l.workingDays} working day${l.workingDays == 1 ? '' : 's'})', {'id': l.id});
        }
      case 'resolve_issue' || 'acknowledge_issue' || 'dismiss_issue':
        final e = find<ExceptionRecord>(data.exceptions, (e) => e.id, p['id']);
        if (e == null) {
          reject('issue not found');
        } else if (e.status != 'pending') {
          reject('that issue is already ${e.status}');
        } else {
          final note = '${p['note'] ?? p['reason'] ?? ''}'.trim();
          final verb = switch (type) { 'resolve_issue' => 'Resolve', 'acknowledge_issue' => 'Acknowledge', _ => 'Dismiss' };
          add('$verb "${e.typeTitle}" for ${nameOf(e.employeeId, e.employeeName)} (${day.format(e.createdAt.toLocal())})'
              '${note.isEmpty ? '' : ' with note: "$note"'}', {'id': e.id, if (note.isNotEmpty) 'note': note});
        }
      case 'add_shift':
        final emp = find<Employee>(data.employees, (e) => e.id, p['employee_id']);
        final start = date(p['start']);
        var end = date(p['end']);
        final site = '${p['site'] ?? emp?.siteLocation ?? ''}'.trim();
        if (emp == null) {
          reject('employee not found');
        } else if (start == null || end == null) {
          reject('start and end times are needed');
        } else if (site.isEmpty) {
          reject('a site is needed');
        } else {
          if (!end.isAfter(start)) end = end.add(const Duration(days: 1));
          final length = end.difference(start);
          if (length > const Duration(hours: 16)) {
            reject('a shift cannot be longer than 16 hours');
          } else {
            add('Add shift for ${emp.fullName}: ${day.format(start)} ${hm.format(start)}-${hm.format(end)} at $site',
                {'employee_id': emp.id, 'start': start.toIso8601String(), 'end': end.toIso8601String(), 'site': site});
          }
        }
      case 'remove_shift':
        final s = find<Shift>(data.shifts, (s) => s.id, p['id']);
        if (s == null) {
          reject('shift not found');
        } else {
          add('Remove shift for ${nameOf(s.employeeId)}: ${day.format(s.startTime.toLocal())} '
              '${hm.format(s.startTime.toLocal())}-${hm.format(s.endTime.toLocal())} at ${s.siteLocation}', {'id': s.id});
        }
      case 'run_compliance_scan':
        add('Run a compliance scan of today\'s rosters and punches', {});
      case 'request_leave':
        final employee = me.isManager && p['employee_id'] != null ? find<Employee>(data.employees, (e) => e.id, p['employee_id']) : me;
        final start = date(p['start_date']);
        final end = date(p['end_date']) ?? start;
        final kind = '${p['leave_type'] ?? ''}'.toLowerCase();
        final reason = '${p['reason'] ?? ''}'.trim();
        if (employee == null) {
          reject('employee not found');
        } else if (!leaveTypes.contains(kind)) {
          reject('unknown leave type "$kind"');
        } else if (start == null || end == null || end.isBefore(start)) {
          reject('valid start and end dates are needed');
        } else {
          final days = DateTime(end.year, end.month, end.day).difference(DateTime(start.year, start.month, start.day)).inDays + 1;
          add('Request $kind leave for ${employee.id == me.id ? 'you' : employee.fullName}: '
              '${day.format(start)} to ${day.format(end)} ($days day${days == 1 ? '' : 's'})${reason.isEmpty ? '' : ', reason: "$reason"'}',
              {'employee_id': employee.id, 'leave_type': kind, 'start_date': start.toIso8601String(), 'end_date': end.toIso8601String(), 'reason': reason});
        }
      case 'withdraw_leave':
        final l = find<LeaveRequest>(data.leave, (l) => l.id, p['id']);
        if (l == null) {
          reject('leave request not found');
        } else if (!l.isPending) {
          reject('only pending requests can be withdrawn');
        } else if (l.employeeId != me.id && !me.isManager) {
          reject('you can only withdraw your own requests');
        } else {
          add('Withdraw ${l.leaveType} leave request for ${l.employeeId == me.id ? 'you' : nameOf(l.employeeId, l.employeeName)}: '
              '${day.format(l.startDate)} to ${day.format(l.endDate)}', {'id': l.id});
        }
      default:
        reject('not something Vigil AI can do');
    }
  }
  return (proposals: proposals, rejected: rejected);
}

final agentActionsProvider = Provider((ref) => AgentActions(ref));

/// Carries out an approved [AgentProposal] through the same tables and rules
/// as the app's own screens. Row-level security still applies.
class AgentActions {
  final Ref _ref;
  AgentActions(this._ref);

  SupabaseClient get _db => Supabase.instance.client;

  /// Returns a confirmation message, or throws with a readable reason.
  Future<String> execute(AgentProposal p) async {
    final me = _ref.read(authProvider).currentUser;
    if (me == null) throw Exception('Please sign in again.');
    final a = p.args;

    Future<void> mustChange(Future<List<Map<String, dynamic>>> q) async {
      if ((await q).isEmpty) throw Exception('Nothing was changed. You may not have permission, or it was already updated.');
    }

    switch (p.type) {
      case 'approve_leave' || 'decline_leave':
        final status = p.type == 'approve_leave' ? 'approved' : 'declined';
        await mustChange(_db.from('leave_requests').update({'status': status}).eq('id', a['id']).eq('status', 'pending').select('id'));
        await _ref.read(leaveStateProvider.notifier).loadLeaveRequests(silent: true);
        return 'Leave $status.';
      case 'resolve_issue' || 'acknowledge_issue' || 'dismiss_issue':
        final status = switch (p.type) { 'resolve_issue' => 'resolved', 'acknowledge_issue' => 'acknowledged', _ => 'ignored' };
        await mustChange(_db
            .from('exception_records')
            .update({
              'status': status,
              if (status == 'resolved') 'resolved_at': DateTime.now().toUtc().toIso8601String(),
              if (a['note'] != null) 'resolution_note': a['note'],
            })
            .eq('id', a['id'])
            .eq('status', 'pending')
            .select('id'));
        await _ref.read(exceptionStateProvider.notifier).fetchExceptions(silent: true);
        return 'Issue ${status == 'ignored' ? 'dismissed' : status}.';
      case 'add_shift':
        final start = DateTime.parse(a['start']), end = DateTime.parse(a['end']);
        final overlap = await _db
            .from('shifts')
            .select('id')
            .eq('employee_id', a['employee_id'])
            .lt('start_time', end.toUtc().toIso8601String())
            .gt('end_time', start.toUtc().toIso8601String())
            .limit(1);
        if (overlap.isNotEmpty) throw Exception('This employee already has a shift at that time.');
        await _db.from('shifts').insert({
          'organization_id': me.organizationId,
          'employee_id': a['employee_id'],
          'site_location': a['site'],
          'start_time': start.toUtc().toIso8601String(),
          'end_time': end.toUtc().toIso8601String(),
        });
        _ref.invalidate(rosterProvider);
        return 'Shift added.';
      case 'remove_shift':
        await mustChange(_db.from('shifts').delete().eq('id', a['id']).select('id'));
        _ref.invalidate(rosterProvider);
        return 'Shift removed.';
      case 'run_compliance_scan':
        final found = await _ref.read(exceptionStateProvider.notifier).runComplianceScan();
        return found == 0 ? 'Scan finished: no new issues.' : 'Scan finished: $found new issue${found == 1 ? '' : 's'} found.';
      case 'request_leave':
        await _ref.read(leaveStateProvider.notifier).createLeaveRequest(
              employeeId: a['employee_id'],
              leaveType: a['leave_type'],
              startDate: DateTime.parse(a['start_date']),
              endDate: DateTime.parse(a['end_date']),
              reason: a['reason'],
            );
        return 'Leave requested. A manager will review it.';
      case 'withdraw_leave':
        await mustChange(_db.from('leave_requests').delete().eq('id', a['id']).eq('status', 'pending').select('id'));
        await _ref.read(leaveStateProvider.notifier).loadLeaveRequests(silent: true);
        return 'Leave request withdrawn.';
      default:
        throw Exception('Vigil AI cannot do that.');
    }
  }
}
