import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../providers/attendance_provider.dart';
import '../providers/geofence_provider.dart';
import '../providers/roster_provider.dart';
import '../services/clock_service.dart';
import '../models/geofence_zone.dart';
import 'premium_card.dart';
import 'animated_button.dart';
import '../theme/ui.dart';

/// Amber that stays readable on both light and dark surfaces.
const _amber = Color(0xFFF59E0B);

class StaffTerminalView extends ConsumerStatefulWidget {
  const StaffTerminalView({super.key});

  @override
  ConsumerState<StaffTerminalView> createState() => _StaffTerminalViewState();
}

class _StaffTerminalViewState extends ConsumerState<StaffTerminalView> {
  Timer? _liveTimer;
  bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    // Ticker to re-render the stopwatch duration every second
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours : $minutes : $seconds';
  }

  String _formatHoursMinutes(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours == 0 && minutes == 0) return '${d.inSeconds}s';
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes}m';
  }

  Future<void> _handleGPSClockIn() async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled on your device.')),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required for GPS clock-in.')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are permanently denied. Please allow location in browser settings.')),
          );
        }
        return;
      }

      // 1. Check if the employee has a scheduled roster shift for today
      final scheduledShift = await ref.read(todayShiftProvider.future);
      if (scheduledShift == null) {
        // If employee has no roster, geofencing is NOT applicable!
        if (mounted) {
          await _showNoRosterScheduledDialog();
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acquiring high-accuracy GPS coordinates...'), duration: Duration(seconds: 2)),
        );
      }

      Position position = await Geolocator.getCurrentPosition();
      final (isWithinZone, matchedZoneName, closestDistance) = await _matchZone(position);

      if (!isWithinZone) {
        // Outside authorized geofence radius
        if (mounted) {
          await _showGeofenceDialog(
            distance: closestDistance,
            onAuthorizeRemote: () async {
              Navigator.of(context).pop();
              await _executeClockEvent(
                eventType: 'clock_in',
                lat: position.latitude,
                lng: position.longitude,
                isGeofenced: false,
                statusNote: 'Clocked in remotely (Flagged for Review)',
              );
            },
          );
        }
        return;
      }

      // Verified within authorized site
      await _executeClockEvent(
        eventType: 'clock_in',
        lat: position.latitude,
        lng: position.longitude,
        isGeofenced: true,
        statusNote: 'GPS Verified at $matchedZoneName. Shift started.',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS verification failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  /// Returns whether [position] is inside any of the organization's geofence
  /// zones, the matched zone name, and the distance to the closest zone's
  /// boundary (null when the organization has no zones configured).
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

  Future<void> _handleClockOut() async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      double? lat;
      double? lng;
      bool isGeofenced = false;

      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)));
          lat = pos.latitude;
          lng = pos.longitude;
          isGeofenced = (await _matchZone(pos)).$1;
        }
      } catch (_) {}

      await _executeClockEvent(
        eventType: 'clock_out',
        lat: lat,
        lng: lng,
        isGeofenced: isGeofenced,
        statusNote: 'Clock Out recorded. Great job today!',
      );
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _executeClockEvent({
    required String eventType,
    double? lat,
    double? lng,
    required bool isGeofenced,
    required String statusNote,
  }) async {
    try {
      await ref.read(clockServiceProvider).recordClockEvent(
        eventType,
        latitude: lat,
        longitude: lng,
        isGeofenced: isGeofenced,
      );
    } on ClockStateException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not record your punch. Check your connection and try again.')));
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                eventType == 'clock_in' ? Icons.check_circle : Icons.logout,
                color: context.fg(),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(statusNote, style: const TextStyle(fontWeight: FontWeight.bold))),
            ],
          ),
          backgroundColor: eventType == 'clock_in' ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _runBreakAction({required bool start}) async {
    setState(() => _isProcessingAction = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final clock = ref.read(clockServiceProvider);
      if (start) {
        await clock.startBreak();
        messenger.showSnackBar(const SnackBar(content: Text('Break started. Enjoy!')));
      } else {
        await clock.endBreak();
        messenger.showSnackBar(const SnackBar(content: Text('Welcome back — break ended.')));
      }
    } on ClockStateException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update your break. Check your connection.')));
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _showNoRosterScheduledDialog() async {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.surfaceHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _amber.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(color: _amber.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: -5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_busy, size: 48, color: _amber),
              ),
              const SizedBox(height: 20),
              Text(
                'No Roster Scheduled Today',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.fg()),
              ),
              const SizedBox(height: 12),
              Text(
                'You have no scheduled shifts on today\'s roster.\n\nSite geofencing and shift clock-in are only applicable for rostered duties. Please contact your administrator or manager to schedule your shift before clocking in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.fg(0.7), fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Acknowledge', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showGeofenceDialog({
    required double? distance,
    required VoidCallback onAuthorizeRemote,
  }) async {
    final distanceText = distance == null
        ? ''
        : distance > 1000 
        ? '${(distance / 1000).toStringAsFixed(1)} km' 
        : '${distance.toStringAsFixed(0)} m';

    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: context.surfaceHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _amber.withValues(alpha: 0.5), width: 2),
            boxShadow: [
              BoxShadow(color: _amber.withValues(alpha: 0.15), blurRadius: 40, spreadRadius: -5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off, size: 48, color: _amber),
              ),
              const SizedBox(height: 20),
              Text(
                'Out of Geofence Zone',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.fg()),
              ),
              const SizedBox(height: 12),
              Text(
                distance == null
                    ? 'Your organization has no work sites set up yet, so your location cannot be verified. Ask a manager to add a geofence zone.'
                    : 'You are $distanceText outside the nearest authorized work site.',
                textAlign: TextAlign.center,
                style: TextStyle(color: context.fg(0.7), fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.fg().withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: _amber),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can still clock in. A remote punch flag will be submitted for manager approval.',
                        style: TextStyle(color: context.fg(0.7), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: context.fg(0.7),
                        side: BorderSide(color: context.fg().withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: onAuthorizeRemote,
                      child: const Text('Clock In Remote', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQRScanner() {
    var handled = false;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 320,
          height: 340,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFF06B6D4), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) async {
                    if (handled) return;
                    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                    if (raw == null) return;
                    handled = true;
                    Navigator.pop(ctx);
                    final zones = await ref.read(geofenceProvider.future);
                    final zone = zones.where((z) => raw == siteQrPayload(z.id)).firstOrNull;
                    if (zone == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('This QR code is not a valid Vigil site code for your organization.')),
                        );
                      }
                      return;
                    }
                    await _executeClockEvent(
                      eventType: 'clock_in',
                      isGeofenced: true,
                      statusNote: 'Site QR verified at ${zone.name}. Shift started.',
                    );
                  },
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: Icon(Icons.close, color: context.fg()),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Scan Site QR Code to Clock In', style: TextStyle(color: context.fg(0.7), fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final attendance = ref.watch(attendanceProvider);
    final isClockedIn = attendance.status == ShiftStatus.clockedIn;
    final isOnBreak = attendance.status == ShiftStatus.onBreak;
    final isOffDuty = attendance.status == ShiftStatus.clockedOut;

    final liveDuration = attendance.currentLiveDuration;
    final durationString = _formatDuration(liveDuration);

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. HERO SHIFT STATUS & LIVE TIMER CARD
              PremiumCard(
                blurRadius: 30,
                opacity: 0.12,
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    // Status Badge Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isClockedIn 
                                    ? const Color(0xFF10B981) 
                                    : (isOnBreak ? _amber : context.fg(0.38)),
                                boxShadow: [
                                  if (isClockedIn)
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.8),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isClockedIn 
                                  ? 'ON DUTY' 
                                  : (isOnBreak ? 'ON BREAK' : 'OFF DUTY'),
                              style: GoogleFonts.outfit(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                                color: isClockedIn 
                                    ? const Color(0xFF10B981) 
                                    : (isOnBreak ? _amber : context.fg(0.6)),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: context.fg().withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: context.fg().withValues(alpha: 0.1)),
                          ),
                          child: Text(
                            DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                            style: TextStyle(fontSize: 12, color: context.fg(0.7), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Digital Shift Stopwatch Display
                    Text(
                      durationString,
                      style: GoogleFonts.firaCode(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                        color: context.fg(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isClockedIn
                          ? 'Shift Duration in Progress (Live)'
                          : (isOnBreak ? 'Shift Paused (Break in Progress)' : 'Total Hours Logged Today'),
                      style: TextStyle(
                        color: isClockedIn 
                            ? const Color(0xFF10B981).withValues(alpha: 0.9) 
                            : (isOnBreak ? _amber : context.fg(0.54)),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Today's Roster Status Banner
                    Builder(builder: (context) {
                      final todayShiftAsync = ref.watch(todayShiftProvider);
                      final scheduledShift = todayShiftAsync.value;

                      if (scheduledShift != null) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event_available, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Scheduled shift: ${DateFormat('h:mm a').format(scheduledShift.startTime.toLocal())} – ${DateFormat('h:mm a').format(scheduledShift.endTime.toLocal())} · ${scheduledShift.siteLocation}',
                                  style: const TextStyle(color: Color(0xFF059669), fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: _amber.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _amber.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_busy, color: _amber, size: 18),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'No shift rostered today. Ask your manager to roster you before clocking in.',
                                  style: TextStyle(color: _amber, fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    }),
                    const SizedBox(height: 28),

                    // Primary Action Buttons
                    if (isOffDuty) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: 220,
                            height: 52,
                            child: AnimatedButton(
                              text: 'GPS CLOCK IN',
                              onPressed: _isProcessingAction ? () {} : _handleGPSClockIn,
                            ),
                          ),
                          SizedBox(
                            width: 180,
                            height: 52,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF06B6D4)),
                              label: const Text('SCAN QR', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF06B6D4),
                                side: BorderSide(color: const Color(0xFF06B6D4).withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                              ),
                              onPressed: _showQRScanner,
                            ),
                          ),
                        ],
                      ),
                    ] else if (isClockedIn) ...[
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(Icons.coffee, color: _amber),
                            label: const Text('START BREAK', style: TextStyle(color: _amber, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: _amber.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isProcessingAction ? null : () => _runBreakAction(start: true),
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.logout),
                            label: const Text('CLOCK OUT', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.redAccent.shade400,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: _isProcessingAction ? null : _handleClockOut,
                          ),
                        ],
                      ),
                    ] else if (isOnBreak) ...[
                      SizedBox(
                        width: 260,
                        height: 52,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('END BREAK & RESUME', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: _isProcessingAction ? null : () => _runBreakAction(start: false),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. METRIC STATS (Today's Key Performance Indicators)
              Builder(builder: (context) {
                final clockIns = attendance.todayEvents.where((e) => e.eventType == 'clock_in').toList();
                final firstIn = clockIns.isNotEmpty ? clockIns.last.eventTime.toLocal() : null;
                // Fair Work: an unpaid meal break is due within 5 hours of starting work.
                final breakDue = !isOffDuty &&
                    attendance.lastClockIn != null &&
                    DateTime.now().difference(attendance.lastClockIn!.toLocal()) - attendance.currentSegmentBreak >
                        const Duration(hours: 5) &&
                    attendance.currentSegmentBreak == Duration.zero &&
                    !isOnBreak;
                final tiles = [
                  _buildMetricTile(
                    icon: Icons.login,
                    iconColor: const Color(0xFF10B981),
                    title: 'First In',
                    value: firstIn != null ? DateFormat('h:mm a').format(firstIn) : '--:--',
                  ),
                  _buildMetricTile(
                    icon: Icons.coffee,
                    iconColor: _amber,
                    title: 'Breaks',
                    value: '${attendance.totalBreakDuration.inMinutes} mins',
                  ),
                  _buildMetricTile(
                    icon: Icons.timer,
                    iconColor: const Color(0xFF3B82F6),
                    title: 'Net Worked',
                    value: _formatHoursMinutes(liveDuration),
                  ),
                  _buildMetricTile(
                    icon: breakDue ? Icons.warning_amber_rounded : Icons.verified_user,
                    iconColor: breakDue ? Colors.redAccent : const Color(0xFF8B5CF6),
                    title: 'Compliance',
                    value: breakDue ? 'Meal break due' : 'On track',
                  ),
                ];
                return LayoutBuilder(builder: (context, c) {
                  const gap = 16.0;
                  final columns = c.maxWidth >= 640 ? 4 : 2;
                  final w = (c.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [for (final t in tiles) SizedBox(width: w, child: t)],
                  );
                });
              }),

              const SizedBox(height: 24),

              // 3. TODAY'S PUNCH TIMELINE / ACTIVITY HISTORY
              PremiumCard(
                blurRadius: 10,
                opacity: 0.08,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Today's Activity Log",
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: context.fg()),
                        ),
                        Text(
                          '${attendance.todayEvents.length} Punches Recorded',
                          style: TextStyle(color: context.fg(0.54), fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Divider(color: context.fg(0.1)),
                    const SizedBox(height: 12),

                    if (attendance.todayEvents.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.history, size: 40, color: context.fg(0.24)),
                              const SizedBox(height: 12),
                              Text('No punches recorded yet today.', style: TextStyle(color: context.fg(0.54))),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: attendance.todayEvents.length,
                        separatorBuilder: (_, _) => Divider(color: context.fg(0.1), height: 16),
                        itemBuilder: (context, index) {
                          final event = attendance.todayEvents[index];
                          final isClockIn = event.eventType == 'clock_in';

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isClockIn 
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15) 
                                      : Colors.redAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isClockIn ? Icons.login : Icons.logout,
                                  color: isClockIn ? const Color(0xFF10B981) : Colors.redAccent,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isClockIn ? 'Shift Clock In' : 'Shift Clock Out',
                                      style: TextStyle(fontWeight: FontWeight.w600, color: context.fg()),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      event.latitude != null 
                                          ? 'GPS: ${event.latitude!.toStringAsFixed(3)}, ${event.longitude!.toStringAsFixed(3)}' 
                                          : (event.isGeofenced ? 'Geofence Verified' : 'Terminal Punch'),
                                      style: TextStyle(fontSize: 12, color: context.fg(0.54)),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: context.fg().withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DateFormat('hh:mm:ss a').format(event.eventTime),
                                  style: GoogleFonts.firaCode(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: context.fg(),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: context.fg().withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.fg().withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: context.fg(0.54), fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.fg(),
            ),
          ),
        ],
      ),
    );
  }
}
