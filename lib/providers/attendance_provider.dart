import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clock_event.dart';
import 'auth_provider.dart';

enum ShiftStatus {
  clockedOut,
  clockedIn,
  onBreak,
}

class AttendanceState {
  final ShiftStatus status;
  final DateTime? lastClockIn;
  final DateTime? lastClockOut;
  final DateTime? activeBreakStart;
  final Duration completedWorkedDuration;
  final Duration totalBreakDuration;
  final List<ClockEvent> todayEvents;
  final List<Map<String, dynamic>> todayBreaks;
  final bool isLoading;

  AttendanceState({
    this.status = ShiftStatus.clockedOut,
    this.lastClockIn,
    this.lastClockOut,
    this.activeBreakStart,
    this.completedWorkedDuration = Duration.zero,
    this.totalBreakDuration = Duration.zero,
    this.todayEvents = const [],
    this.todayBreaks = const [],
    this.isLoading = false,
  });

  /// Calculates real-time total worked duration including ongoing shift
  Duration get currentLiveDuration {
    if (status == ShiftStatus.clockedIn && lastClockIn != null) {
      final ongoing = DateTime.now().difference(lastClockIn!);
      final total = completedWorkedDuration + ongoing;
      return total.isNegative ? Duration.zero : total;
    } else if (status == ShiftStatus.onBreak && lastClockIn != null && activeBreakStart != null) {
      // Frozen at the start of break
      final ongoingBeforeBreak = activeBreakStart!.difference(lastClockIn!);
      final total = completedWorkedDuration + ongoingBeforeBreak;
      return total.isNegative ? Duration.zero : total;
    }
    return completedWorkedDuration;
  }

  AttendanceState copyWith({
    ShiftStatus? status,
    DateTime? lastClockIn,
    DateTime? lastClockOut,
    DateTime? activeBreakStart,
    Duration? completedWorkedDuration,
    Duration? totalBreakDuration,
    List<ClockEvent>? todayEvents,
    List<Map<String, dynamic>>? todayBreaks,
    bool? isLoading,
  }) {
    return AttendanceState(
      status: status ?? this.status,
      lastClockIn: lastClockIn ?? this.lastClockIn,
      lastClockOut: lastClockOut ?? this.lastClockOut,
      activeBreakStart: activeBreakStart ?? this.activeBreakStart,
      completedWorkedDuration: completedWorkedDuration ?? this.completedWorkedDuration,
      totalBreakDuration: totalBreakDuration ?? this.totalBreakDuration,
      todayEvents: todayEvents ?? this.todayEvents,
      todayBreaks: todayBreaks ?? this.todayBreaks,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AttendanceNotifier extends StateNotifier<AttendanceState> {
  final Ref _ref;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _eventsSubscription;
  RealtimeChannel? _breaksSubscription;

  AttendanceNotifier(this._ref) : super(AttendanceState(isLoading: true)) {
    loadTodayAttendance();
    _setupRealtime();
  }

  void _setupRealtime() {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;

    _eventsSubscription = _supabase
        .channel('attendance_clock_events_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'clock_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: user.id,
          ),
          callback: (_) => loadTodayAttendance(),
        )
        .subscribe();

    _breaksSubscription = _supabase
        .channel('attendance_breaks_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'breaks',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'employee_id',
            value: user.id,
          ),
          callback: (_) => loadTodayAttendance(),
        )
        .subscribe();
  }

  Future<void> loadTodayAttendance() async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) {
      state = AttendanceState();
      return;
    }

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      // Fetch today's clock events
      final eventsRes = await _supabase
          .from('clock_events')
          .select()
          .eq('employee_id', user.id)
          .gte('event_time', todayStart)
          .order('event_time', ascending: true);

      final events = (eventsRes as List).map((e) => ClockEvent.fromJson(e)).toList();

      // Fetch today's breaks
      final breaksRes = await _supabase
          .from('breaks')
          .select()
          .eq('employee_id', user.id)
          .gte('start_time', todayStart)
          .order('start_time', ascending: true);

      final breaks = List<Map<String, dynamic>>.from(breaksRes);

      // Compute total breaks
      int totalBreakMinutes = 0;
      DateTime? activeBreak;
      for (final b in breaks) {
        if (b['end_time'] == null) {
          activeBreak = DateTime.tryParse(b['start_time'].toString());
        } else {
          totalBreakMinutes += (b['duration_minutes'] as num?)?.toInt() ?? 0;
        }
      }

      // Compute status & completed worked duration
      ShiftStatus computedStatus = ShiftStatus.clockedOut;
      DateTime? currentClockIn;
      DateTime? lastClockOut;
      Duration completedWorked = Duration.zero;

      DateTime? segmentClockIn;
      for (final event in events) {
        if (event.eventType == 'clock_in') {
          segmentClockIn = event.eventTime;
          currentClockIn = event.eventTime;
        } else if (event.eventType == 'clock_out' && segmentClockIn != null) {
          final diff = event.eventTime.difference(segmentClockIn);
          if (!diff.isNegative) {
            completedWorked += diff;
          }
          lastClockOut = event.eventTime;
          segmentClockIn = null;
        }
      }

      if (segmentClockIn != null) {
        // Still clocked in
        computedStatus = activeBreak != null ? ShiftStatus.onBreak : ShiftStatus.clockedIn;
      } else {
        computedStatus = ShiftStatus.clockedOut;
      }

      // Subtract completed breaks from completed duration
      final netCompletedWorked = completedWorked - Duration(minutes: totalBreakMinutes);

      state = AttendanceState(
        status: computedStatus,
        lastClockIn: segmentClockIn ?? currentClockIn,
        lastClockOut: lastClockOut,
        activeBreakStart: activeBreak,
        completedWorkedDuration: netCompletedWorked.isNegative ? Duration.zero : netCompletedWorked,
        totalBreakDuration: Duration(minutes: totalBreakMinutes),
        todayEvents: events.reversed.toList(), // Most recent first for display
        todayBreaks: breaks,
        isLoading: false,
      );
    } catch (e) {
      print('Error loading attendance: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  void refresh() {
    loadTodayAttendance();
  }

  @override
  void dispose() {
    _eventsSubscription?.unsubscribe();
    _breaksSubscription?.unsubscribe();
    super.dispose();
  }
}

final attendanceProvider = StateNotifierProvider<AttendanceNotifier, AttendanceState>((ref) {
  return AttendanceNotifier(ref);
});
