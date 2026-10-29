import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clock_event.dart';
import 'auth_provider.dart';

enum StaffWorkStatus {
  clockedIn,
  onBreak,
  clockedOut,
}

class StaffLiveAttendance {
  final String employeeId;
  final String fullName;
  final String email;
  final String role;
  final String siteLocation;
  final StaffWorkStatus status;
  final DateTime? shiftStartTime;
  final DateTime? breakStartTime;
  final Duration completedWorkedDuration;
  final Duration totalBreakDuration;

  /// Completed break time inside the currently open clock-in segment.
  final Duration currentSegmentBreak;
  final double? latitude;
  final double? longitude;
  final bool isGeofenced;
  final DateTime? lastEventTime;

  StaffLiveAttendance({
    required this.employeeId,
    required this.fullName,
    required this.email,
    required this.role,
    required this.siteLocation,
    required this.status,
    this.shiftStartTime,
    this.breakStartTime,
    this.completedWorkedDuration = Duration.zero,
    this.totalBreakDuration = Duration.zero,
    this.currentSegmentBreak = Duration.zero,
    this.latitude,
    this.longitude,
    this.isGeofenced = false,
    this.lastEventTime,
  });

  /// Live ticking duration including ongoing active shift
  Duration get currentDuration {
    final now = DateTime.now();
    if (status == StaffWorkStatus.clockedIn && shiftStartTime != null) {
      final ongoing = now.difference(shiftStartTime!.toLocal()) - currentSegmentBreak;
      final total = completedWorkedDuration + ongoing;
      return total.isNegative ? Duration.zero : total;
    } else if (status == StaffWorkStatus.onBreak && shiftStartTime != null && breakStartTime != null) {
      final ongoingBeforeBreak = breakStartTime!.toLocal().difference(shiftStartTime!.toLocal()) - currentSegmentBreak;
      final total = completedWorkedDuration + ongoingBeforeBreak;
      return total.isNegative ? Duration.zero : total;
    }
    return completedWorkedDuration;
  }
}

class WorkforceState {
  final List<StaffLiveAttendance> staffList;
  final Map<String, String> employeeNames; // ID -> Full Name
  final bool isLoading;
  final String? error;

  WorkforceState({
    this.staffList = const [],
    this.employeeNames = const {},
    this.isLoading = false,
    this.error,
  });

  int get onShiftCount => staffList.where((s) => s.status == StaffWorkStatus.clockedIn).length;
  int get onBreakCount => staffList.where((s) => s.status == StaffWorkStatus.onBreak).length;
  int get offDutyCount => staffList.where((s) => s.status == StaffWorkStatus.clockedOut).length;
  int get totalStaffCount => staffList.length;

  WorkforceState copyWith({
    List<StaffLiveAttendance>? staffList,
    Map<String, String>? employeeNames,
    bool? isLoading,
    String? error,
  }) {
    return WorkforceState(
      staffList: staffList ?? this.staffList,
      employeeNames: employeeNames ?? this.employeeNames,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

class WorkforceNotifier extends StateNotifier<WorkforceState> {
  final Ref _ref;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _workforceChannel;
  Timer? _debounce;

  WorkforceNotifier(this._ref) : super(WorkforceState(isLoading: true)) {
    loadWorkforce();
    _setupRealtime();
  }

  /// Coalesces bursts of realtime events into a single reload.
  void _scheduleReload() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) loadWorkforce();
    });
  }

  void _setupRealtime() {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;
    final orgFilter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'organization_id',
      value: user.organizationId,
    );
    final channel = _supabase.channel('live_workforce_${user.organizationId}');
    for (final table in const ['clock_events', 'breaks', 'employees']) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: orgFilter,
        callback: (_) => _scheduleReload(),
      );
    }
    _workforceChannel = channel..subscribe();
  }

  Future<void> loadWorkforce() async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) {
      state = WorkforceState();
      return;
    }

    try {
      final now = DateTime.now();
      final todayStartLocal = DateTime(now.year, now.month, now.day);
      final todayStartUtc = todayStartLocal.toUtc().toIso8601String();

      // 1. Fetch all employees in current organization (or all if system_admin)
      final employeesRes = await _supabase
          .from('employees')
          .select()
          .eq('organization_id', user.organizationId)
          .order('full_name', ascending: true);

      final employees = List<Map<String, dynamic>>.from(employeesRes);
      final Map<String, String> namesMap = {};
      for (final emp in employees) {
        namesMap[emp['id']] = emp['full_name'] ?? emp['email'] ?? 'Unknown';
      }

      // 2. Fetch all today's clock_events for organization
      final eventsRes = await _supabase
          .from('clock_events')
          .select()
          .eq('organization_id', user.organizationId)
          .gte('event_time', todayStartUtc)
          .order('event_time', ascending: true);
      final allEvents = (eventsRes as List).map((e) => ClockEvent.fromJson(e)).toList();

      // 3. Fetch all today's breaks for organization
      final breaksRes = await _supabase
          .from('breaks')
          .select()
          .eq('organization_id', user.organizationId)
          .gte('start_time', todayStartUtc)
          .order('start_time', ascending: true);
      final allBreaks = List<Map<String, dynamic>>.from(breaksRes);

      // 4. Calculate status for each employee
      final List<StaffLiveAttendance> liveStaff = [];

      for (final emp in employees) {
        final empId = emp['id'] as String;
        final empEvents = allEvents.where((e) => e.employeeId == empId).toList();
        final empBreaks = allBreaks.where((b) => b['employee_id'] == empId).toList();

        // Calculate breaks
        int totalBreakMinutes = 0;
        DateTime? activeBreak;
        for (final b in empBreaks) {
          if (b['end_time'] == null) {
            activeBreak = DateTime.tryParse(b['start_time'].toString());
          } else {
            totalBreakMinutes += (b['duration_minutes'] as num?)?.toInt() ?? 0;
          }
        }

        // Calculate shift status and worked hours
        StaffWorkStatus status = StaffWorkStatus.clockedOut;
        DateTime? currentShiftStart;
        Duration completedWorked = Duration.zero;
        DateTime? segmentClockIn;
        double? lastLat;
        double? lastLng;
        bool isGeofenced = false;
        DateTime? lastEventTime;

        for (final event in empEvents) {
          lastLat = event.latitude;
          lastLng = event.longitude;
          isGeofenced = event.isGeofenced;
          lastEventTime = event.eventTime;

          if (event.eventType == 'clock_in') {
            segmentClockIn = event.eventTime;
            currentShiftStart = event.eventTime;
          } else if (event.eventType == 'clock_out' && segmentClockIn != null) {
            final diff = event.eventTime.difference(segmentClockIn);
            if (!diff.isNegative) {
              completedWorked += diff;
            }
            segmentClockIn = null;
          }
        }

        if (segmentClockIn != null) {
          status = activeBreak != null ? StaffWorkStatus.onBreak : StaffWorkStatus.clockedIn;
        } else {
          status = StaffWorkStatus.clockedOut;
        }

        int currentSegmentBreakMinutes = 0;
        final openSegmentStart = segmentClockIn;
        if (openSegmentStart != null) {
          for (final b in empBreaks) {
            final start = DateTime.tryParse(b['start_time'].toString());
            if (b['end_time'] != null && start != null && !start.isBefore(openSegmentStart)) {
              currentSegmentBreakMinutes += (b['duration_minutes'] as num?)?.toInt() ?? 0;
            }
          }
        }
        final netWorked = completedWorked - Duration(minutes: totalBreakMinutes - currentSegmentBreakMinutes);

        liveStaff.add(StaffLiveAttendance(
          employeeId: empId,
          fullName: emp['full_name'] ?? 'Staff',
          email: emp['email'] ?? '',
          role: emp['role'] ?? 'staff',
          siteLocation: emp['site_location'] ?? 'Remote',
          status: status,
          shiftStartTime: segmentClockIn ?? currentShiftStart,
          breakStartTime: activeBreak,
          completedWorkedDuration: netWorked.isNegative ? Duration.zero : netWorked,
          totalBreakDuration: Duration(minutes: totalBreakMinutes),
          currentSegmentBreak: Duration(minutes: currentSegmentBreakMinutes),
          latitude: lastLat,
          longitude: lastLng,
          isGeofenced: isGeofenced,
          lastEventTime: lastEventTime,
        ));
      }

      // Sort: Clocked In first, then On Break, then Off Duty
      liveStaff.sort((a, b) {
        if (a.status == StaffWorkStatus.clockedIn && b.status != StaffWorkStatus.clockedIn) return -1;
        if (b.status == StaffWorkStatus.clockedIn && a.status != StaffWorkStatus.clockedIn) return 1;
        if (a.status == StaffWorkStatus.onBreak && b.status == StaffWorkStatus.clockedOut) return -1;
        if (b.status == StaffWorkStatus.onBreak && a.status == StaffWorkStatus.clockedOut) return 1;
        return a.fullName.compareTo(b.fullName);
      });

      state = WorkforceState(
        staffList: liveStaff,
        employeeNames: namesMap,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('Error in loadWorkforce: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void refresh() {
    loadWorkforce();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _workforceChannel?.unsubscribe();
    super.dispose();
  }
}

final workforceProvider = StateNotifierProvider<WorkforceNotifier, WorkforceState>((ref) {
  // Rebuild (and re-subscribe) whenever the signed-in user changes.
  ref.watch(authProvider.select((s) => s.currentUser?.id));
  return WorkforceNotifier(ref);
});
