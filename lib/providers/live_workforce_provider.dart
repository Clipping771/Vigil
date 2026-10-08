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
    this.latitude,
    this.longitude,
    this.isGeofenced = false,
    this.lastEventTime,
  });

  /// Live ticking duration including ongoing active shift
  Duration get currentDuration {
    if (status == StaffWorkStatus.clockedIn && shiftStartTime != null) {
      final ongoing = DateTime.now().difference(shiftStartTime!);
      final total = completedWorkedDuration + ongoing;
      return total.isNegative ? Duration.zero : total;
    } else if (status == StaffWorkStatus.onBreak && shiftStartTime != null && breakStartTime != null) {
      final ongoingBeforeBreak = breakStartTime!.difference(shiftStartTime!);
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

  WorkforceNotifier(this._ref) : super(WorkforceState(isLoading: true)) {
    loadWorkforce();
    _setupRealtime();
  }

  void _setupRealtime() {
    // Listen to changes on clock_events, breaks, and employees
    _workforceChannel = _supabase.channel('public_live_workforce_feed')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'clock_events',
        callback: (payload) {
          loadWorkforce();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'breaks',
        callback: (payload) {
          loadWorkforce();
        },
      )
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'employees',
        callback: (payload) {
          loadWorkforce();
        },
      )
      ..subscribe();
  }

  Future<void> loadWorkforce() async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) {
      state = WorkforceState();
      return;
    }

    try {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      // 1. Fetch all employees in current organization (or all if system_admin)
      var query = _supabase.from('employees').select();
      if (user.role != 'system_admin') {
        query = query.eq('organization_id', user.organizationId);
      }
      final employeesRes = await query.order('full_name', ascending: true);

      final employees = List<Map<String, dynamic>>.from(employeesRes);
      final Map<String, String> namesMap = {};
      for (final emp in employees) {
        namesMap[emp['id']] = emp['full_name'] ?? emp['email'] ?? 'Unknown';
      }

      // 2. Fetch all today's clock_events for organization
      var eventsFilter = _supabase
          .from('clock_events')
          .select()
          .gte('event_time', todayStart);

      if (user.role != 'system_admin') {
        eventsFilter = eventsFilter.eq('organization_id', user.organizationId);
      }
      final eventsRes = await eventsFilter.order('event_time', ascending: true);
      final allEvents = (eventsRes as List).map((e) => ClockEvent.fromJson(e)).toList();

      // 3. Fetch all today's breaks for organization
      var breaksFilter = _supabase
          .from('breaks')
          .select()
          .gte('start_time', todayStart);

      if (user.role != 'system_admin') {
        breaksFilter = breaksFilter.eq('organization_id', user.organizationId);
      }
      final breaksRes = await breaksFilter.order('start_time', ascending: true);
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

        final netWorked = completedWorked - Duration(minutes: totalBreakMinutes);

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
      print('Error in loadWorkforce: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void refresh() {
    loadWorkforce();
  }

  @override
  void dispose() {
    _workforceChannel?.unsubscribe();
    super.dispose();
  }
}

final workforceProvider = StateNotifierProvider<WorkforceNotifier, WorkforceState>((ref) {
  return WorkforceNotifier(ref);
});
