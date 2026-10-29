import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/exception_record.dart';
import '../providers/auth_provider.dart';
import '../providers/exception_provider.dart';
import '../providers/live_workforce_provider.dart';
import '../services/agent_service.dart';
import '../widgets/app_shell.dart';
import '../widgets/staff_terminal_view.dart';
import '../widgets/ui_kit.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  int _activeTab = 0; // 0: team overview, 1: my punch clock
  String _filter = 'active'; // active | critical | resolved | all
  bool _scanning = false;
  String? _aiFor;
  String? _aiSuggestion;
  Timer? _autoScan;

  @override
  void initState() {
    super.initState();
    // Managers: look for no-shows and forgotten clock-outs automatically while
    // the dashboard is open (the server also runs this every 5 minutes).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !(ref.read(authProvider).currentUser?.isManager ?? false)) return;
      _silentScan();
      _autoScan = Timer.periodic(const Duration(minutes: 5), (_) => _silentScan());
    });
  }

  @override
  void dispose() {
    _autoScan?.cancel();
    super.dispose();
  }

  Future<void> _silentScan() async {
    try {
      await ref.read(exceptionServiceProvider).runComplianceScan();
    } catch (_) {
      // Offline or no permission — the manual scan button reports errors.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    final isManager = user?.isManager ?? false;
    final showTerminal = !isManager || _activeTab == 1;
    final compact = isCompact(context);

    final tabs = isManager
        ? [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.groups_outlined), label: compact ? null : const Text('Team')),
                  ButtonSegment(value: 1, icon: const Icon(Icons.fingerprint), label: compact ? null : const Text('My punch clock')),
                ],
                selected: {_activeTab},
                onSelectionChanged: (v) => setState(() => _activeTab = v.first),
              ),
            ),
          ]
        : const <Widget>[];

    if (showTerminal) {
      return AppPage(
        title: isManager ? 'Dashboard' : 'My shift',
        actions: tabs,
        maxWidth: 880,
        children: const [StaffTerminalView()],
      );
    }

    return AppPage(
      title: 'Dashboard',
      actions: tabs,
      children: [
        _Greeting(name: user?.fullName ?? ''),
        const SizedBox(height: 20),
        _buildStats(),
        const SizedBox(height: 8),
        _buildWhoIsWorking(),
        _buildExceptions(),
      ],
    );
  }

  // ---------------------------------------------------------------- stats
  Widget _buildStats() {
    final workforce = ref.watch(workforceProvider);
    final exceptions = ref.watch(exceptionStateProvider);
    return ResponsiveGrid(
      minItemWidth: 150,
      children: [
        StatTile(
          icon: Icons.work_outline,
          label: 'On shift',
          value: '${workforce.onShiftCount}',
          caption: 'Clocked in right now',
          tone: Tone.success,
        ),
        StatTile(
          icon: Icons.coffee_outlined,
          label: 'On break',
          value: '${workforce.onBreakCount}',
          caption: 'Meal or rest break',
          tone: Tone.warning,
        ),
        StatTile(
          icon: Icons.report_outlined,
          label: 'Open issues',
          value: '${exceptions.activeCount}',
          caption: exceptions.criticalCount > 0 ? '${exceptions.criticalCount} critical' : 'Needs review',
          tone: exceptions.activeCount > 0 ? Tone.danger : Tone.neutral,
        ),
        StatTile(
          icon: Icons.groups_outlined,
          label: 'Team',
          value: '${workforce.totalStaffCount}',
          caption: 'People in your organization',
          tone: Tone.primary,
        ),
      ],
    );
  }

  // ------------------------------------------------------- who is working
  Widget _buildWhoIsWorking() {
    final workforce = ref.watch(workforceProvider);
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          "Who's working",
          subtitle: 'Updates live as people clock in and out',
          actions: [StatusChip('${workforce.onShiftCount} on shift', tone: Tone.success, icon: Icons.circle)],
        ),
        Card(
          child: workforce.isLoading && workforce.staffList.isEmpty
              ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              : workforce.staffList.isEmpty
                  ? const EmptyState(icon: Icons.groups_outlined, title: 'No team members yet', message: 'Invite people from the Staff page.')
                  : Column(
                      children: [
                        for (var i = 0; i < workforce.staffList.length; i++) ...[
                          if (i > 0) const Divider(indent: 72),
                          Builder(builder: (context) {
                            final s = workforce.staffList[i];
                            final (label, tone) = switch (s.status) {
                              StaffWorkStatus.clockedIn => ('On shift', Tone.success),
                              StaffWorkStatus.onBreak => ('On break', Tone.warning),
                              StaffWorkStatus.clockedOut => ('Off', Tone.neutral),
                            };
                            final d = s.currentDuration;
                            final worked = d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';
                            final detail = s.status == StaffWorkStatus.clockedOut || s.shiftStartTime == null
                                ? s.siteLocation
                                : 'Since ${DateFormat('h:mm a').format(s.shiftStartTime!.toLocal())} · $worked · ${s.siteLocation}';
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              leading: UserAvatar(name: s.fullName, radius: 20),
                              title: Text(s.fullName, style: t.titleSmall),
                              subtitle: Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (s.status != StaffWorkStatus.clockedOut && !isCompact(context)) ...[
                                    Tooltip(
                                      message: s.isGeofenced ? 'Location verified at site' : 'Location not verified',
                                      child: Icon(
                                        s.isGeofenced ? Icons.verified_outlined : Icons.location_off_outlined,
                                        size: 18,
                                        color: (s.isGeofenced ? Tone.success : Tone.warning).accent(context),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  StatusChip(label, tone: tone),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
        ),
      ],
    );
  }

  // ----------------------------------------------------------- exceptions
  Widget _buildExceptions() {
    final state = ref.watch(exceptionStateProvider);
    final items = state.allExceptions.where((e) {
      return switch (_filter) {
        'active' => !e.isResolved && !e.isIgnored,
        'critical' => (e.isCritical || e.isHigh) && !e.isResolved && !e.isIgnored,
        'resolved' => e.isResolved,
        _ => true,
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'Compliance issues',
          subtitle: 'Late starts, overtime, missed breaks and location problems',
          actions: [
            OutlinedButton.icon(
              onPressed: _scanning ? null : _runScan,
              icon: _scanning
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.fact_check_outlined, size: 18),
              label: const Text('Run compliance scan'),
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (key, label) in [
              ('active', 'Open · ${state.activeCount}'),
              ('critical', 'High priority · ${state.criticalCount + state.highCount}'),
              ('resolved', 'Resolved · ${state.resolvedCount}'),
              ('all', 'All · ${state.allExceptions.length}'),
            ])
              FilterChip(
                label: Text(label),
                selected: _filter == key,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.isLoading && state.allExceptions.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else if (state.error != null && state.allExceptions.isEmpty)
          Card(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load issues',
              action: OutlinedButton(
                onPressed: () => ref.read(exceptionStateProvider.notifier).fetchExceptions(),
                child: const Text('Try again'),
              ),
            ),
          )
        else if (items.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.task_alt,
              title: 'All clear',
              message: 'No compliance issues match this filter.',
            ),
          )
        else
          for (final ex in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: _exceptionCard(ex)),
      ],
    );
  }

  Widget _exceptionCard(ExceptionRecord ex) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final severityTone = ex.isCritical || ex.isHigh ? Tone.danger : (ex.isMedium ? Tone.warning : Tone.info);
    final statusTone = ex.isResolved ? Tone.success : (ex.isAcknowledged ? Tone.primary : (ex.isIgnored ? Tone.neutral : Tone.warning));
    final showAi = _aiFor == ex.id;
    final (sevFg, sevBg) = severityTone.colors(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: sevBg, shape: BoxShape.circle),
                  child: Icon(_iconFor(ex.exceptionType), size: 20, color: sevFg),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(ex.typeTitle, style: t.titleMedium),
                          StatusChip(_capitalize(ex.severity), tone: severityTone),
                          StatusChip(_capitalize(ex.status), tone: statusTone),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(ex.description ?? '', style: t.bodyMedium),
                      const SizedBox(height: 8),
                      Text(
                        [
                          ex.employeeName ?? 'Unknown employee',
                          if (ex.siteLocation != null) ex.siteLocation!,
                          DateFormat('d MMM, h:mm a').format(ex.createdAt.toLocal()),
                        ].join('  ·  '),
                        style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (ex.resolutionNote != null && ex.resolutionNote!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text('Note: ${ex.resolutionNote}',
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (!ex.isResolved && !ex.isIgnored) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _showResolveDialog(ex),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Resolve'),
                    ),
                    if (ex.isPending)
                      OutlinedButton(
                        onPressed: () => _runAction(
                          () => ref.read(exceptionServiceProvider).acknowledgeException(ex.id),
                          'Marked as acknowledged.',
                        ),
                        child: const Text('Acknowledge'),
                      ),
                    TextButton.icon(
                      onPressed: showAi ? null : () => _askAi(ex),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                      label: const Text('Ask AI'),
                    ),
                  ],
                ),
              ),
            ],
            if (showAi) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.only(left: 56),
                child: _aiSuggestion == null
                    ? const InfoBanner('Asking Vigil AI for a recommendation…', icon: Icons.auto_awesome_outlined)
                    : Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.auto_awesome, size: 18, color: cs.onSecondaryContainer),
                              const SizedBox(width: 8),
                              Text('AI recommendation', style: t.titleSmall?.copyWith(color: cs.onSecondaryContainer)),
                            ]),
                            const SizedBox(height: 8),
                            Text(_aiSuggestion!, style: t.bodyMedium?.copyWith(color: cs.onSecondaryContainer)),
                            const SizedBox(height: 4),
                            Text('AI-generated — check before acting.',
                                style: t.bodySmall?.copyWith(color: cs.onSecondaryContainer.withValues(alpha: 0.75))),
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, children: [
                              FilledButton(
                                onPressed: () {
                                  final note = 'AI-assisted: $_aiSuggestion';
                                  setState(() => _aiFor = _aiSuggestion = null);
                                  _runAction(
                                    () => ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: note),
                                    'Issue resolved.',
                                  );
                                },
                                child: const Text('Resolve with this note'),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _aiFor = _aiSuggestion = null),
                                child: const Text('Dismiss'),
                              ),
                            ]),
                          ],
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------- actions
  Future<void> _runScan() async {
    setState(() => _scanning = true);
    try {
      final inserted = await ref.read(exceptionServiceProvider).runComplianceScan();
      if (mounted) showMessage(context, inserted > 0 ? 'Scan complete: $inserted new issue(s) found.' : 'Scan complete: no new issues.');
    } catch (_) {
      if (mounted) showMessage(context, 'The compliance scan failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    try {
      await action();
      if (mounted) showMessage(context, success);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not update this issue. You may not have permission.');
    }
  }

  Future<void> _askAi(ExceptionRecord ex) async {
    setState(() {
      _aiFor = ex.id;
      _aiSuggestion = null;
    });
    try {
      final text = await ref.read(agentServiceProvider).suggestResolution(
            type: ex.typeTitle,
            severity: ex.severity,
            description: ex.description ?? '',
            employeeName: ex.employeeName,
          );
      if (mounted && _aiFor == ex.id) setState(() => _aiSuggestion = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _aiFor = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is AgentUnavailable ? e.message : 'Vigil AI is unavailable right now.'),
        action: SnackBarAction(label: 'Settings', onPressed: () => context.go('/settings')),
      ));
    }
  }

  Future<void> _showResolveDialog(ExceptionRecord ex) async {
    final note = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ex.typeTitle),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ex.description ?? '', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 20),
              TextField(
                controller: note,
                maxLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Resolution note (optional)',
                  hintText: 'e.g. Overtime approved by site manager',
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'dismiss'), child: const Text('Dismiss issue')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'resolve'), child: const Text('Resolve')),
        ],
      ),
    );
    final text = note.text.trim().isEmpty ? null : note.text.trim();
    note.dispose();
    if (result == 'resolve') {
      await _runAction(() => ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: text), 'Issue resolved.');
    } else if (result == 'dismiss') {
      await _runAction(() => ref.read(exceptionServiceProvider).ignoreException(ex.id, reason: text), 'Issue dismissed.');
    }
  }

  static IconData _iconFor(String type) => switch (type) {
        'missed_clock_in' => Icons.alarm_off_outlined,
        'late_clock_in' => Icons.schedule,
        'early_departure' => Icons.directions_walk,
        'missed_clock_out' => Icons.timer_off_outlined,
        'excessive_overtime' => Icons.more_time,
        'roster_breach' => Icons.event_busy_outlined,
        'geofence_violation' => Icons.location_off_outlined,
        'fair_work_compliance_breach' => Icons.bedtime_outlined,
        'leave_roster_conflict' => Icons.event_note_outlined,
        'fraud_risk' => Icons.gpp_maybe_outlined,
        _ => Icons.report_outlined,
      };

  static String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _Greeting extends StatelessWidget {
  final String name;
  const _Greeting({required this.name});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final part = hour < 12 ? 'morning' : (hour < 17 ? 'afternoon' : 'evening');
    final first = name.split(' ').first;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text('Good $part${first.isEmpty ? '' : ', $first'}', style: t.headlineMedium),
        const SizedBox(height: 4),
        Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
            style: t.bodyLarge?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
