import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../models/clock_event.dart';
import '../models/shift.dart';
import '../models/exception_record.dart';
import 'exception_engine.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';

class ClockService {
  final Ref _ref;
  final _supabase = Supabase.instance.client;

  ClockService(this._ref);

  Future<void> simulateClockEvent(String eventType) async {
    final user = _ref.read(authProvider).currentUser;
    final settings = _ref.read(settingsProvider);
    if (user == null) return;

    // 1. Fetch current active shift for user
    final now = DateTime.now();
    final shiftsResponse = await _supabase
        .from('shifts')
        .select()
        .eq('employee_id', user.id)
        .gte('end_time', now.subtract(const Duration(hours: 12)).toIso8601String())
        .lte('start_time', now.add(const Duration(hours: 12)).toIso8601String())
        .order('start_time')
        .limit(1);

    Shift? activeShift;
    if (shiftsResponse.isNotEmpty) {
      activeShift = Shift.fromJson(shiftsResponse.first);
    }

    // 2. Create the clock event
    final clockEvent = ClockEvent(
      id: Uuid().v4(),
      organizationId: user.organizationId,
      employeeId: user.id,
      eventType: eventType,
      eventTime: now,
      createdAt: now,
    );

    // Save clock event to database
    await _supabase.from('clock_events').insert({
      'organization_id': clockEvent.organizationId,
      'employee_id': clockEvent.employeeId,
      'event_type': clockEvent.eventType,
      'event_time': clockEvent.eventTime.toIso8601String(),
    });

    // 3. Run through Exception Engine
    final exception = await ExceptionEngine.processClockEvent(
      event: clockEvent,
      scheduledShift: activeShift,
      allowedLateMinutes: settings.allowedLateMinutes,
      allowedOvertimeMinutes: settings.allowedOvertimeMinutes,
      organizationId: user.organizationId,
    );

    // 4. Insert exception if detected
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
  }
}

final clockServiceProvider = Provider<ClockService>((ref) {
  return ClockService(ref);
});
