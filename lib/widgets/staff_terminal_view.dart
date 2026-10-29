import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/geofence_zone.dart';
import '../providers/attendance_provider.dart';
import '../providers/geofence_provider.dart';
import '../providers/roster_provider.dart';
import '../services/clock_service.dart';
import '../providers/auth_provider.dart';
import '../providers/exception_provider.dart';
import 'review_trail.dart';
import 'ui_kit.dart';

/// Personal punch clock: status, live timer, clock in/out, breaks, today's log.
class StaffTerminalView extends ConsumerStatefulWidget {
  const StaffTerminalView({super.key});

  @override
  ConsumerState<StaffTerminalView> createState() => _StaffTerminalViewState();
}

class _StaffTerminalViewState extends ConsumerState<StaffTerminalView> {
  Timer? _ticker;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Re-render the live timer every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) =>
      '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  static String _hm(Duration d) => d.inHours > 0 ? '${d.inHours}h ${d.inMinutes % 60}m' : '${d.inMinutes}m';

  // ------------------------------------------------------------ location
  /// Whether [position] is inside one of the organization's zones, the zone
  /// name, and the distance to the nearest zone boundary (null: no zones).
  Future<(bool, String?, double?)> _matchZone(Position position) async {
    final zones = await ref.read(geofenceProvider.future);
    double? closest;
    for (final zone in zones) {
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, zone.latitude, zone.longitude);
      if (distance <= zone.radiusMeters) return (true, zone.name, 0.0);
      final toBoundary = distance - zone.radiusMeters;
      if (closest == null || toBoundary < closest) closest = toBoundary;
    }
    return (false, null, closest);
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) showMessage(context, 'Turn on location services to clock in.');
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) showMessage(context, 'Allow location access in your browser or device settings to clock in.');
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------- actions
  Future<void> _clockIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _ensureLocationPermission()) return;

      final shift = await ref.read(todayShiftProvider.future);
      if (shift == null) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.event_busy_outlined),
              title: const Text('No shift today'),
              content: const Text('You are not rostered today. Ask your manager to add a shift before you clock in.'),
              actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
            ),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final (inside, zoneName, distance) = await _matchZone(position);
      if (!mounted) return;

      if (!inside) {
        final where = distance == null
            ? 'Your organization has no work sites set up yet, so your location cannot be verified.'
            : 'You are ${distance > 1000 ? '${(distance / 1000).toStringAsFixed(1)} km' : '${distance.toStringAsFixed(0)} m'} outside the nearest work site.';
        final proceed = await confirmDialog(
          context,
          title: 'Outside work site',
          message: '$where You can still clock in — your manager will be asked to review it.',
          confirmLabel: 'Clock in anyway',
        );
        if (!proceed) return;
        await _record('clock_in', position.latitude, position.longitude, false, 'Clocked in. Flagged for manager review.');
        return;
      }

      await _record('clock_in', position.latitude, position.longitude, true, 'Clocked in at $zoneName.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not get your location. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut() async {
    if (_busy) return;
    final ok = await confirmDialog(context, title: 'Clock out?', message: 'This ends your shift for now.', confirmLabel: 'Clock out');
    if (!ok) return;
    setState(() => _busy = true);
    try {
      double? lat, lng;
      var inside = false;
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)));
          lat = pos.latitude;
          lng = pos.longitude;
          inside = (await _matchZone(pos)).$1;
        }
      } catch (_) {
        // Clock-out still proceeds without a location fix.
      }
      await _record('clock_out', lat, lng, inside, 'Clocked out. See you next time!');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _record(String type, double? lat, double? lng, bool geofenced, String success) async {
    try {
      await ref.read(clockServiceProvider).recordClockEvent(type, latitude: lat, longitude: lng, isGeofenced: geofenced);
      if (mounted) showMessage(context, success);
    } on ClockStateException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not record your punch. Check your connection and try again.');
    }
  }

  Future<void> _break({required bool start}) async {
    setState(() => _busy = true);
    try {
      final clock = ref.read(clockServiceProvider);
      start ? await clock.startBreak() : await clock.endBreak();
      if (mounted) showMessage(context, start ? 'Break started.' : 'Break ended. Welcome back!');
    } on ClockStateException catch (e) {
      if (mounted) showMessage(context, e.message);
    } catch (_) {
      if (mounted) showMessage(context, 'Could not update your break. Check your connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _scanQr() {
    var handled = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Scan site QR code'),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 300,
            height: 300,
            child: MobileScanner(
              onDetect: (capture) async {
                if (handled) return;
                final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                if (raw == null) return;
                handled = true;
                Navigator.pop(ctx);
                final zones = await ref.read(geofenceProvider.future);
                final zone = zones.where((z) => raw == siteQrPayload(z.id)).firstOrNull;
                if (zone == null) {
                  if (mounted) showMessage(context, 'That is not a Vigil site code for your organization.');
                  return;
                }
                await _record('clock_in', null, null, true, 'Clocked in at ${zone.name}.');
              },
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel'))],
      ),
    );
  }

  /// Tells the employee when a manager reviews one of their issues, or when a
  /// new one is raised (e.g. right after a late clock-in).
  void _notifyIssueChanges(ExceptionState? prev, ExceptionState next, String myId) {
    if (prev == null || prev.isLoading) return;
    final before = {for (final e in prev.allExceptions) e.id: e};
    for (final e in next.allExceptions.where((e) => e.employeeId == myId)) {
      final old = before[e.id];
      String? message;
      if (old == null) {
        message = 'New issue on your record: ${e.typeTitle}.';
      } else if (old.status != e.status && !e.isPending) {
        final who = e.reviewedByName != null ? ' by ${e.reviewedByName}' : '';
        final note = (e.resolutionNote ?? '').trim().isEmpty ? '' : ' — “${e.resolutionNote!.trim()}”';
        message = '${e.typeTitle}: ${e.reviewVerb.toLowerCase()}$who$note';
      }
      if (message != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
        return;
      }
    }
  }

  Widget _myIssues(String myId) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final mine = ref.watch(exceptionStateProvider).allExceptions.where((e) => e.employeeId == myId).toList();
    final open = mine.where((e) => e.isPending || e.isAcknowledged).length;
    final shown = mine.take(10).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          'My issues',
          subtitle: mine.isEmpty ? 'Compliance issues on your record appear here' : '$open open · ${mine.length} total',
        ),
        Card(
          child: shown.isEmpty
              ? const EmptyState(icon: Icons.task_alt, title: 'No issues', message: 'Nice work — nothing on your record.')
              : Column(
                  children: [
                    for (var i = 0; i < shown.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, endIndent: 16),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Builder(builder: (context) {
                          final e = shown[i];
                          final (label, tone) = e.isResolved
                              ? ('Resolved', Tone.success)
                              : e.isIgnored
                                  ? ('Dismissed', Tone.neutral)
                                  : e.isAcknowledged
                                      ? ('Seen by manager', Tone.primary)
                                      : ('Awaiting review', Tone.warning);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(e.typeTitle, style: t.titleSmall),
                                  StatusChip(label, tone: tone),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(e.description ?? '', style: t.bodyMedium),
                              const SizedBox(height: 4),
                              Text(DateFormat('d MMM, h:mm a').format(e.createdAt.toLocal()),
                                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                              if (!e.isPending) ...[const SizedBox(height: 10), ReviewTrail(e)],
                            ],
                          );
                        }),
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final myId = ref.watch(authProvider.select((s) => s.currentUser?.id)) ?? '';
    ref.listen<ExceptionState>(exceptionStateProvider, (prev, next) => _notifyIssueChanges(prev, next, myId));
    final a = ref.watch(attendanceProvider);
    final shift = ref.watch(todayShiftProvider).value;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final clockedIn = a.status == ShiftStatus.clockedIn;
    final onBreak = a.status == ShiftStatus.onBreak;
    final off = a.status == ShiftStatus.clockedOut;
    final live = a.currentLiveDuration;

    final (statusLabel, statusTone) = clockedIn
        ? ('On shift', Tone.success)
        : (onBreak ? ('On break', Tone.warning) : ('Off shift', Tone.neutral));

    final clockIns = a.todayEvents.where((e) => e.eventType == 'clock_in').toList();
    final firstIn = clockIns.isNotEmpty ? clockIns.last.eventTime.toLocal() : null;
    // Fair Work: an unpaid meal break is due within 5 hours of starting work.
    final breakDue = clockedIn &&
        a.lastClockIn != null &&
        a.currentSegmentBreak == Duration.zero &&
        DateTime.now().difference(a.lastClockIn!.toLocal()) > const Duration(hours: 5);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
            child: Column(
              children: [
                Row(
                  children: [
                    StatusChip(statusLabel, tone: statusTone, icon: Icons.circle),
                    const Spacer(),
                    Text(DateFormat('EEE, d MMM').format(DateTime.now()), style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  _clock(live),
                  style: t.displayMedium?.copyWith(fontWeight: FontWeight.w400, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
                const SizedBox(height: 4),
                Text(
                  off ? 'Worked today' : (onBreak ? 'Paused while on break' : 'Time on shift today'),
                  style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                if (shift != null)
                  InfoBanner(
                    'Rostered ${DateFormat('h:mm a').format(shift.startTime.toLocal())} – ${DateFormat('h:mm a').format(shift.endTime.toLocal())} at ${shift.siteLocation}',
                    tone: Tone.primary,
                    icon: Icons.event_available_outlined,
                  )
                else
                  const InfoBanner(
                    'No shift rostered today. Ask your manager to roster you before clocking in.',
                    tone: Tone.warning,
                    icon: Icons.event_busy_outlined,
                  ),
                if (breakDue) ...[
                  const SizedBox(height: 12),
                  const InfoBanner(
                    'You have worked over 5 hours without a break. Please take your meal break.',
                    tone: Tone.danger,
                    icon: Icons.coffee_outlined,
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (off) ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(180, 52)),
                        onPressed: _busy ? null : _clockIn,
                        icon: _busy
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.login),
                        label: const Text('Clock in'),
                      ),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(160, 52)),
                        onPressed: _busy ? null : _scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan site QR'),
                      ),
                    ] else if (clockedIn) ...[
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                        onPressed: _busy ? null : () => _break(start: true),
                        icon: const Icon(Icons.coffee_outlined),
                        label: const Text('Start break'),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(160, 52), backgroundColor: cs.error, foregroundColor: cs.onError),
                        onPressed: _busy ? null : _clockOut,
                        icon: const Icon(Icons.logout),
                        label: const Text('Clock out'),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        style: FilledButton.styleFrom(minimumSize: const Size(200, 52)),
                        onPressed: _busy ? null : () => _break(start: false),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('End break'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        ResponsiveGrid(
          minItemWidth: 150,
          spacing: 12,
          children: [
            StatTile(icon: Icons.login, label: 'First in', value: firstIn != null ? DateFormat('h:mm a').format(firstIn) : '—', tone: Tone.success),
            StatTile(icon: Icons.coffee_outlined, label: 'Breaks', value: _hm(a.totalBreakDuration), tone: Tone.warning),
            StatTile(icon: Icons.timer_outlined, label: 'Worked', value: _hm(live), tone: Tone.primary),
            StatTile(
              icon: breakDue ? Icons.warning_amber_rounded : Icons.verified_outlined,
              label: 'Compliance',
              value: breakDue ? 'Break due' : 'On track',
              tone: breakDue ? Tone.danger : Tone.info,
            ),
          ],
        ),
        SectionHeader("Today's activity", subtitle: '${a.todayEvents.length} punches'),
        Card(
          child: a.todayEvents.isEmpty
              ? const EmptyState(icon: Icons.history, title: 'No punches yet today', message: 'Your clock-ins and clock-outs will appear here.')
              : Column(
                  children: [
                    for (var i = 0; i < a.todayEvents.length; i++) ...[
                      if (i > 0) const Divider(indent: 72),
                      Builder(builder: (context) {
                        final e = a.todayEvents[i];
                        final isIn = e.eventType == 'clock_in';
                        final tone = isIn ? Tone.success : Tone.primary;
                        final (fg, bg) = tone.colors(context);
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(backgroundColor: bg, child: Icon(isIn ? Icons.login : Icons.logout, size: 20, color: fg)),
                          title: Text(isIn ? 'Clocked in' : 'Clocked out', style: t.titleSmall),
                          subtitle: Text(
                            e.isGeofenced ? 'Location verified' : (e.latitude != null ? 'Outside work site' : 'No location'),
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          trailing: Text(DateFormat('h:mm a').format(e.eventTime.toLocal()), style: t.titleSmall),
                        );
                      }),
                    ],
                  ],
                ),
        ),
        _myIssues(myId),
      ],
    );
  }
}
