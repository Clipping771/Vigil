import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/clock_event.dart';
import '../models/shift.dart';
import 'exception_engine.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/attendance_provider.dart';

class ClockService {
  final Ref _ref;
  final _supabase = Supabase.instance.client;

  ClockService(this._ref);

  Future<void> simulateClockEvent(
    String eventType, {
    double? latitude,
    double? longitude,
    bool isGeofenced = false,
  }) async {
    final user = _ref.read(authProvider).currentUser;
    final settings = _ref.read(settingsProvider);
    if (user == null) return;

    final now = DateTime.now();

    // 1. Fetch current active shift for user
    final shiftsResponse = await _supabase
        .from('shifts')
        .select()
        .eq('employee_id', user.id)
        .gte('end_time', now.toUtc().subtract(const Duration(hours: 12)).toIso8601String())
        .lte('start_time', now.toUtc().add(const Duration(hours: 12)).toIso8601String())
        .order('start_time')
        .limit(1);

    Shift? activeShift;
    if (shiftsResponse.isNotEmpty) {
      activeShift = Shift.fromJson(shiftsResponse.first);
    }

    final eventId = const Uuid().v4();
    final clockEvent = ClockEvent(
      id: eventId,
      organizationId: user.organizationId,
      employeeId: user.id,
      eventType: eventType,
      eventTime: now,
      latitude: latitude,
      longitude: longitude,
      isGeofenced: isGeofenced,
      createdAt: now,
    );

    // 2. Save clock event to database with GPS coordinates and Geofence status
    await _supabase.from('clock_events').insert({
      'id': eventId,
      'organization_id': clockEvent.organizationId,
      'employee_id': clockEvent.employeeId,
      'event_type': clockEvent.eventType,
      'event_time': clockEvent.eventTime.toUtc().toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'is_geofenced': isGeofenced,
    });

    // 3. Process exception if out-of-boundary geofence (only applicable if a shift is rostered)
    if (!isGeofenced && latitude != null && longitude != null && activeShift != null) {
      await _supabase.from('exception_records').insert({
        'organization_id': user.organizationId,
        'employee_id': user.id,
        'exception_type': 'geofence_violation',
        'severity': 'high',
        'shift_id': activeShift.id,
        'status': 'pending',
        'description': 'Clock-$eventType registered outside authorized geofence boundary for shift at ${activeShift.siteLocation}.',
      });
    }

    // 4. Run through Exception Engine
    final exception = await ExceptionEngine.processClockEvent(
      event: clockEvent,
      scheduledShift: activeShift,
      allowedLateMinutes: settings.allowedLateMinutes,
      allowedOvertimeMinutes: settings.allowedOvertimeMinutes,
      organizationId: user.organizationId,
    );

    // 5. Insert exception if detected
    if (exception != null) {
      await _supabase.from('exception_records').insert({
        'organization_id': exception.organizationId,
        'employee_id': exception.employeeId,
        'exception_type': exception.exceptionType,
        'severity': exception.severity,
        'shift_id': exception.shiftId,
        'status': exception.status,
        'description': exception.description,
      });
    }

    // 6. Refresh attendance state immediately
    _ref.read(attendanceProvider.notifier).refresh();
  }

  /// Starts an active break (status becomes onBreak)
  Future<void> startBreak({String breakType = 'meal'}) async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final shiftsResponse = await _supabase
        .from('shifts')
        .select()
        .eq('employee_id', user.id)
        .gte('end_time', now.toUtc().subtract(const Duration(hours: 12)).toIso8601String())
        .lte('start_time', now.toUtc().add(const Duration(hours: 12)).toIso8601String())
        .order('start_time')
        .limit(1);

    String? shiftId;
    if (shiftsResponse.isNotEmpty) {
      shiftId = shiftsResponse.first['id'];
    }

    await _supabase.from('breaks').insert({
      'organization_id': user.organizationId,
      'employee_id': user.id,
      'shift_id': shiftId,
      'start_time': now.toUtc().toIso8601String(),
      'break_type': breakType,
    });

    _ref.read(attendanceProvider.notifier).refresh();
  }

  /// Ends the current active break
  Future<void> endBreak() async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final activeBreaks = await _supabase
        .from('breaks')
        .select()
        .eq('employee_id', user.id)
        .isFilter('end_time', null)
        .order('start_time', ascending: false)
        .limit(1);

    if (activeBreaks.isNotEmpty) {
      final breakId = activeBreaks.first['id'];
      final startTime = DateTime.parse(activeBreaks.first['start_time']).toLocal();
      final duration = now.difference(startTime).inMinutes;

      await _supabase.from('breaks').update({
        'end_time': now.toUtc().toIso8601String(),
        'duration_minutes': duration < 1 ? 1 : duration,
      }).eq('id', breakId);
    }

    _ref.read(attendanceProvider.notifier).refresh();
  }

  /// Records a completed quick break (for instant compliance logs)
  Future<void> recordBreak({int durationMinutes = 30, String breakType = 'meal'}) async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final shiftsResponse = await _supabase
        .from('shifts')
        .select()
        .eq('employee_id', user.id)
        .gte('end_time', now.toUtc().subtract(const Duration(hours: 12)).toIso8601String())
        .lte('start_time', now.toUtc().add(const Duration(hours: 12)).toIso8601String())
        .order('start_time')
        .limit(1);

    String? shiftId;
    if (shiftsResponse.isNotEmpty) {
      shiftId = shiftsResponse.first['id'];
    }

    await _supabase.from('breaks').insert({
      'organization_id': user.organizationId,
      'employee_id': user.id,
      'shift_id': shiftId,
      'start_time': now.subtract(Duration(minutes: durationMinutes)).toUtc().toIso8601String(),
      'end_time': now.toUtc().toIso8601String(),
      'duration_minutes': durationMinutes,
      'break_type': breakType,
    });

    _ref.read(attendanceProvider.notifier).refresh();
  }
}

final clockServiceProvider = Provider<ClockService>((ref) {
  return ClockService(ref);
});
