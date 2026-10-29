import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/employee.dart';
import '../models/leave_request.dart';
import '../models/shift.dart';
import '../providers/auth_provider.dart';
import '../providers/leave_provider.dart';
import '../providers/roster_provider.dart';
import '../providers/staff_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';

const _leaveTypes = {
  'annual': ('Annual leave', Icons.beach_access_outlined),
  'sick': ("Sick / carer's leave", Icons.medical_services_outlined),
  'unpaid': ('Unpaid leave', Icons.hourglass_empty),
  'compassionate': ('Compassionate leave', Icons.volunteer_activism_outlined),
  'maternity': ('Parental leave', Icons.child_friendly_outlined),
  'paternity': ('Parental leave', Icons.child_friendly_outlined),
  'other': ('Other leave', Icons.event_note_outlined),
};

/// Fair Work (Australia) yearly entitlements for full-time employees, in days.
const _annualEntitlement = 20;
const _sickEntitlement = 10;

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  String _status = 'all'; // all | pending | approved | declined
  bool _mineOnly = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(leaveStateProvider);
    final me = ref.watch(authProvider).currentUser;
    final isManager = me?.isManager ?? false;
    final shifts = ref.watch(rosterProvider).value ?? const <Shift>[];

    final all = state.requests;
    final visible = all.where((r) {
      if ((_mineOnly || !isManager) && r.employeeId != me?.id) return false;
      if (_status == 'pending' && !r.isPending) return false;
      if (_status == 'approved' && !r.isApproved) return false;
      if (_status == 'declined' && !r.isDeclined) return false;
      if (_query.isNotEmpty) {
        final q = _query.toLowerCase();
        final hay = '${r.employeeName ?? ''} ${r.employeeEmail ?? ''} ${r.reason ?? ''} ${r.leaveType}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    final year = DateTime.now().year;
    final mine = all.where((r) => r.employeeId == me?.id && r.isApproved && r.startDate.year == year);
    final usedAnnual = mine.where((r) => r.leaveType == 'annual').fold<int>(0, (s, r) => s + r.durationDays);
    final usedSick = mine.where((r) => r.leaveType == 'sick').fold<int>(0, (s, r) => s + r.durationDays);
    final scope = isManager && !_mineOnly ? all : all.where((r) => r.employeeId == me?.id).toList();

    return AppPage(
      title: 'Leave',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh),
          onPressed: () => ref.read(leaveStateProvider.notifier).loadLeaveRequests(),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new-leave',
        onPressed: _newRequest,
        icon: const Icon(Icons.add),
        label: const Text('Request leave'),
      ),
      children: [
        const SizedBox(height: 8),
        ResponsiveGrid(
          minItemWidth: 150,
          children: [
            StatTile(
              icon: Icons.beach_access_outlined,
              label: 'Annual leave left',
              value: '${(_annualEntitlement - usedAnnual).clamp(0, 99)} days',
              caption: '$usedAnnual of $_annualEntitlement used in $year',
              tone: Tone.primary,
            ),
            StatTile(
              icon: Icons.medical_services_outlined,
              label: 'Sick leave left',
              value: '${(_sickEntitlement - usedSick).clamp(0, 99)} days',
              caption: '$usedSick of $_sickEntitlement used in $year',
              tone: Tone.info,
            ),
            StatTile(
              icon: Icons.hourglass_top,
              label: isManager ? 'Awaiting approval' : 'My pending requests',
              value: '${scope.where((r) => r.isPending).length}',
              caption: 'Pending decisions',
              tone: Tone.warning,
            ),
            StatTile(
              icon: Icons.event_available_outlined,
              label: 'On leave today',
              value: '${all.where((r) => r.isOngoingToday).length}',
              caption: 'Approved leave covering today',
              tone: Tone.success,
            ),
          ],
        ),
        SectionHeader(isManager ? 'Requests' : 'My requests'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (key, label) in [
              ('all', 'All · ${scope.length}'),
              ('pending', 'Pending · ${scope.where((r) => r.isPending).length}'),
              ('approved', 'Approved · ${scope.where((r) => r.isApproved).length}'),
              ('declined', 'Declined · ${scope.where((r) => r.isDeclined).length}'),
            ])
              FilterChip(
                label: Text(label),
                selected: _status == key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _status = key),
              ),
            if (isManager)
              FilterChip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: const Text('Only mine'),
                selected: _mineOnly,
                onSelected: (v) => setState(() => _mineOnly = v),
              ),
            SizedBox(
              width: isCompact(context) ? double.infinity : 280,
              child: SearchBar(
                hintText: 'Search people or notes',
                leading: const Icon(Icons.search),
                elevation: const WidgetStatePropertyAll(0),
                side: WidgetStatePropertyAll(BorderSide(color: Theme.of(context).colorScheme.outline)),
                backgroundColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surface),
                constraints: const BoxConstraints(minHeight: 40, maxHeight: 40),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.isLoading && all.isEmpty)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else if (state.error != null && all.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load leave requests',
              action: OutlinedButton(
                onPressed: () => ref.read(leaveStateProvider.notifier).loadLeaveRequests(),
                child: const Text('Try again'),
              ),
            ),
          )
        else if (visible.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.beach_access_outlined,
              title: all.isEmpty ? 'No leave requests yet' : 'Nothing matches',
              message: all.isEmpty ? 'Requests you or your team submit will appear here.' : 'Try a different filter.',
            ),
          )
        else
          for (final r in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _requestCard(r, me, isManager, shifts),
            ),
      ],
    );
  }

  Widget _requestCard(LeaveRequest r, Employee? me, bool isManager, List<Shift> shifts) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final own = r.employeeId == me?.id;
    final (typeLabel, typeIcon) = _leaveTypes[r.leaveType] ?? _leaveTypes['other']!;
    final (statusLabel, statusTone) = r.isApproved
        ? ('Approved', Tone.success)
        : (r.isDeclined ? ('Declined', Tone.danger) : ('Pending', Tone.warning));
    final fmt = DateFormat('d MMM yyyy');
    final dates = r.durationDays == 1 ? fmt.format(r.startDate) : '${fmt.format(r.startDate)} – ${fmt.format(r.endDate)}';

    final leaveStart = DateTime(r.startDate.year, r.startDate.month, r.startDate.day);
    final leaveEnd = DateTime(r.endDate.year, r.endDate.month, r.endDate.day).add(const Duration(days: 1));
    final conflicts = shifts.where((s) => s.employeeId == r.employeeId && s.startTime.isBefore(leaveEnd) && s.endTime.isAfter(leaveStart)).length;

    final canDecide = r.isPending && isManager && (!own || (me?.isOrgAdmin ?? false));
    final canWithdraw = r.isPending && (own || isManager);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                UserAvatar(name: r.employeeName ?? '?', radius: 20),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(r.employeeName ?? 'Unknown', style: t.titleMedium),
                          if (own) const StatusChip('You', tone: Tone.primary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(typeIcon, size: 16, color: cs.onSurfaceVariant),
                          Text('$typeLabel  ·  $dates  ·  ${r.durationDays} ${r.durationDays == 1 ? 'day' : 'days'}',
                              style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(statusLabel, tone: statusTone),
                if (canWithdraw)
                  IconButton(
                    tooltip: 'Withdraw request',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _withdraw(r),
                  ),
              ],
            ),
            if (r.reason != null && r.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Text('“${r.reason}”', style: t.bodyMedium),
              ),
            ],
            if (conflicts > 0 && !r.isDeclined) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: InfoBanner(
                  '$conflicts rostered ${conflicts == 1 ? 'shift overlaps' : 'shifts overlap'} this leave and will need cover.',
                  tone: Tone.warning,
                  icon: Icons.warning_amber_rounded,
                ),
              ),
            ],
            if (r.isOngoingToday) ...[
              const SizedBox(height: 12),
              const Padding(padding: EdgeInsets.only(left: 56), child: StatusChip('On leave today', tone: Tone.info)),
            ],
            if (canDecide) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _decide(r, 'approved'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Approve'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _decide(r, 'declined'),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Decline'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _decide(LeaveRequest r, String status) async {
    try {
      await ref.read(leaveStateProvider.notifier).updateStatus(r.id, status);
      if (mounted) showMessage(context, status == 'approved' ? 'Leave approved.' : 'Leave declined.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not update this request. You may not have permission.');
    }
  }

  Future<void> _withdraw(LeaveRequest r) async {
    final ok = await confirmDialog(
      context,
      title: 'Withdraw request?',
      message: 'This removes the leave request. It cannot be undone.',
      confirmLabel: 'Withdraw',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(leaveStateProvider.notifier).deleteLeaveRequest(r.id);
      if (mounted) showMessage(context, 'Request withdrawn.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not withdraw this request.');
    }
  }

  Future<void> _newRequest() async {
    final me = ref.read(authProvider).currentUser;
    if (me == null) return;
    final staff = me.isManager ? await ref.read(staffProvider.future).catchError((_) => <Employee>[]) : <Employee>[];
    if (!mounted) return;

    var employeeId = me.id;
    var type = 'annual';
    final tomorrow = DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
    var range = DateTimeRange(start: tomorrow, end: tomorrow.add(const Duration(days: 2)));
    final reason = TextEditingController();
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setLocal) {
          final days = range.end.difference(range.start).inDays + 1;
          final fmt = DateFormat('EEE, d MMM yyyy');
          return AlertDialog(
            title: const Text('Request leave'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (staff.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        initialValue: employeeId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Employee'),
                        items: [
                          DropdownMenuItem(value: me.id, child: Text('${me.fullName} (me)')),
                          for (final e in staff.where((e) => e.id != me.id))
                            DropdownMenuItem(value: e.id, child: Text(e.fullName)),
                        ],
                        onChanged: (v) => setLocal(() => employeeId = v ?? employeeId),
                      ),
                      const SizedBox(height: 16),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Type of leave'),
                      items: [
                        for (final key in const ['annual', 'sick', 'unpaid', 'compassionate', 'maternity', 'other'])
                          DropdownMenuItem(
                            value: key,
                            child: Row(children: [
                              Icon(_leaveTypes[key]!.$2, size: 18),
                              const SizedBox(width: 12),
                              Text(_leaveTypes[key]!.$1),
                            ]),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => type = v ?? type),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime.now().subtract(const Duration(days: 30)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                          initialDateRange: range,
                        );
                        if (picked != null) setLocal(() => range = picked);
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Dates',
                          suffixIcon: const Icon(Icons.calendar_month_outlined),
                          helperText: '$days ${days == 1 ? 'day' : 'days'}',
                        ),
                        child: Text(days == 1 ? fmt.format(range.start) : '${fmt.format(range.start)} – ${fmt.format(range.end)}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reason,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Note (optional)', alignLabelWithHint: true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setLocal(() => saving = true);
                        try {
                          await ref.read(leaveStateProvider.notifier).createLeaveRequest(
                                employeeId: employeeId,
                                leaveType: type,
                                startDate: range.start,
                                endDate: range.end,
                                reason: reason.text,
                              );
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          if (mounted) showMessage(this.context, 'Leave request submitted.');
                        } catch (e) {
                          setLocal(() => saving = false);
                          if (mounted) showMessage(this.context, e.toString().replaceFirst('Exception: ', ''));
                        }
                      },
                child: saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
    reason.dispose();
  }
}
