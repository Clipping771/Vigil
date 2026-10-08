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
import 'premium_card.dart';
import 'animated_button.dart';

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

      // Check geofence zones against the scheduled shift's authorized site
      final geofenceAsync = ref.read(geofenceProvider);
      final zones = geofenceAsync.value ?? [];

      bool isWithinZone = false;
      String? matchedZoneName;
      double? closestDistance;

      for (var zone in zones) {
        final distance = Geolocator.distanceBetween(position.latitude, position.longitude, zone.latitude, zone.longitude);
        if (closestDistance == null || distance < closestDistance) {
          closestDistance = distance;
        }
        if (distance <= zone.radiusMeters) {
          isWithinZone = true;
          matchedZoneName = zone.name;
          break;
        }
      }

      if (!isWithinZone) {
        // Outside authorized geofence radius
        if (mounted) {
          await _showGeofenceDialog(
            distance: closestDistance ?? 0,
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

  Future<void> _handleClockOut() async {
    if (_isProcessingAction) return;
    setState(() => _isProcessingAction = true);

    try {
      double? lat;
      double? lng;
      bool isGeofenced = false;

      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          final pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 4));
          lat = pos.latitude;
          lng = pos.longitude;
          isGeofenced = true;
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
    await ref.read(clockServiceProvider).simulateClockEvent(
      eventType,
      latitude: lat,
      longitude: lng,
      isGeofenced: isGeofenced,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                eventType == 'clock_in' ? Icons.check_circle : Icons.logout,
                color: Colors.white,
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

  Future<void> _showNoRosterScheduledDialog() async {
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 440,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amberAccent.withOpacity(0.5), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.amberAccent.withOpacity(0.15), blurRadius: 40, spreadRadius: -5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.event_busy, size: 48, color: Colors.amberAccent),
              ),
              const SizedBox(height: 20),
              Text(
                'No Roster Scheduled Today',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                'You have no scheduled shifts on today\'s roster.\n\nSite geofencing and shift clock-in are only applicable for rostered duties. Please contact your administrator or manager to schedule your shift before clocking in.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.6),
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
    required double distance,
    required VoidCallback onAuthorizeRemote,
  }) async {
    final distanceText = distance > 1000 
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
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.amberAccent.withOpacity(0.5), width: 2),
            boxShadow: [
              BoxShadow(color: Colors.amberAccent.withOpacity(0.15), blurRadius: 40, spreadRadius: -5),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.location_off, size: 48, color: Colors.amberAccent),
              ),
              const SizedBox(height: 20),
              Text(
                'Out of Geofence Zone',
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'You are currently $distanceText away from the nearest authorized site boundary.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.5),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Colors.amberAccent),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'You can still clock in. A remote punch flag will be submitted for manager approval.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
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
                        foregroundColor: Colors.white70,
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
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
            border: Border.all(color: const Color(0xFF00E5FF), width: 2),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                MobileScanner(
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      Navigator.pop(ctx);
                      _executeClockEvent(
                        eventType: 'clock_in',
                        isGeofenced: true,
                        statusNote: 'QR Code Verified. Shift started.',
                      );
                    }
                  },
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Text('Scan Site QR Code to Clock In', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
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
                                    : (isOnBreak ? Colors.amberAccent : Colors.white38),
                                boxShadow: [
                                  if (isClockedIn)
                                    BoxShadow(
                                      color: const Color(0xFF10B981).withOpacity(0.8),
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
                                    : (isOnBreak ? Colors.amberAccent : Colors.white60),
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: Text(
                            DateFormat('EEE, d MMM yyyy').format(DateTime.now()),
                            style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.w500),
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
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isClockedIn
                          ? 'Shift Duration in Progress (Live)'
                          : (isOnBreak ? 'Shift Paused (Break in Progress)' : 'Total Hours Logged Today'),
                      style: TextStyle(
                        color: isClockedIn 
                            ? const Color(0xFF10B981).withOpacity(0.9) 
                            : (isOnBreak ? Colors.amberAccent : Colors.white54),
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
                            color: const Color(0xFF10B981).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.35)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event_available, color: Color(0xFF10B981), size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Scheduled Shift: ${DateFormat('hh:mm a').format(scheduledShift.startTime.toLocal())} – ${DateFormat('hh:mm a').format(scheduledShift.endTime.toLocal())} @ ${scheduledShift.siteLocation}',
                                style: const TextStyle(color: Color(0xFF10B981), fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_busy, color: Colors.amberAccent, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'No Roster Scheduled Today (Admin must assign a shift before clocking in)',
                                style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        );
                      }
                    }),
                    const SizedBox(height: 28),

                    // Primary Action Buttons
                    if (isOffDuty) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 220,
                            height: 52,
                            child: AnimatedButton(
                              text: 'GPS CLOCK IN',
                              onPressed: _isProcessingAction ? () {} : _handleGPSClockIn,
                            ),
                          ),
                          const SizedBox(width: 20),
                          SizedBox(
                            width: 180,
                            height: 52,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF)),
                              label: const Text('SCAN QR', style: TextStyle(fontWeight: FontWeight.bold)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00E5FF),
                                side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5)),
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
                            icon: const Icon(Icons.coffee, color: Colors.amberAccent),
                            label: const Text('LOG 30-MIN MEAL BREAK', style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.amberAccent.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            onPressed: () async {
                              await ref.read(clockServiceProvider).recordBreak(durationMinutes: 30, breakType: 'meal');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('30-Minute Meal Break recorded for Fair Work compliance.'), backgroundColor: Colors.green),
                                );
                              }
                            },
                          ),
                          FilledButton.icon(
                            icon: const Icon(Icons.logout, color: Colors.white),
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
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () async {
                            await ref.read(clockServiceProvider).endBreak();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // 2. METRIC STATS ROW (Today's Key Performance Indicators)
              Row(
                children: [
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.login,
                      iconColor: const Color(0xFF10B981),
                      title: 'First In',
                      value: attendance.todayEvents.isNotEmpty
                          ? DateFormat('hh:mm a').format(attendance.todayEvents.last.eventTime)
                          : '--:--',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.coffee,
                      iconColor: Colors.amberAccent,
                      title: 'Breaks',
                      value: '${attendance.totalBreakDuration.inMinutes} mins',
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.timer,
                      iconColor: const Color(0xFF3B82F6),
                      title: 'Net Worked',
                      value: _formatHoursMinutes(liveDuration),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildMetricTile(
                      icon: Icons.verified_user,
                      iconColor: const Color(0xFF8B5CF6),
                      title: 'Compliance',
                      value: 'Fair Work OK',
                    ),
                  ),
                ],
              ),

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
                          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          '${attendance.todayEvents.length} Punches Recorded',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 12),

                    if (attendance.todayEvents.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.history, size: 40, color: Colors.white24),
                              const SizedBox(height: 12),
                              const Text('No punches recorded yet today.', style: TextStyle(color: Colors.white54)),
                            ],
                          ),
                        ),
                      ),
                    ] else ...[
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: attendance.todayEvents.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 16),
                        itemBuilder: (context, index) {
                          final event = attendance.todayEvents[index];
                          final isClockIn = event.eventType == 'clock_in';

                          return Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: isClockIn 
                                      ? const Color(0xFF10B981).withOpacity(0.15) 
                                      : Colors.redAccent.withOpacity(0.15),
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
                                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      event.latitude != null 
                                          ? 'GPS: ${event.latitude!.toStringAsFixed(3)}, ${event.longitude!.toStringAsFixed(3)}' 
                                          : (event.isGeofenced ? 'Geofence Verified' : 'Terminal Punch'),
                                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DateFormat('hh:mm:ss a').format(event.eventTime),
                                  style: GoogleFonts.firaCode(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.white,
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
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
