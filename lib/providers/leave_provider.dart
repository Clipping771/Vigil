import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/leave_request.dart';
import 'auth_provider.dart';

class LeaveState {
  final List<LeaveRequest> requests;
  final bool isLoading;
  final String? error;

  LeaveState({
    this.requests = const [],
    this.isLoading = false,
    this.error,
  });

  int get pendingCount => requests.where((r) => r.isPending).length;
  int get approvedCount => requests.where((r) => r.isApproved).length;
  int get declinedCount => requests.where((r) => r.isDeclined).length;
  int get activeTodayCount => requests.where((r) => r.isOngoingToday).length;

  LeaveState copyWith({
    List<LeaveRequest>? requests,
    bool? isLoading,
    String? error,
  }) {
    return LeaveState(
      requests: requests ?? this.requests,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class LeaveNotifier extends StateNotifier<LeaveState> {
  final Ref _ref;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _realtimeChannel;
  Timer? _debounce;

  LeaveNotifier(this._ref) : super(LeaveState(isLoading: true)) {
    loadLeaveRequests();
    _setupRealtime();
  }

  void _setupRealtime() {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;
    _realtimeChannel = _supabase.channel('leave_requests_${user.organizationId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'leave_requests',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'organization_id',
          value: user.organizationId,
        ),
        callback: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) loadLeaveRequests(silent: true);
          });
        },
      )
      ..subscribe();
  }

  Future<void> loadLeaveRequests({bool silent = false}) async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) {
      state = LeaveState(requests: [], isLoading: false);
      return;
    }

    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      // 1. Fetch leave requests with joined employee data
      final response = await _supabase
          .from('leave_requests')
          .select('*, employees(full_name, email, role, site_location)')
          .eq('organization_id', user.organizationId)
          .order('start_date', ascending: false);
      
      final list = (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
      state = LeaveState(requests: list, isLoading: false);
    } catch (e) {
      // Fallback: If Supabase foreign key join encounters an issue, fetch employees separately
      try {
        final plainRes = await _supabase
            .from('leave_requests')
            .select()
            .eq('organization_id', user.organizationId)
            .order('start_date', ascending: false);

        final empRes = await _supabase
            .from('employees')
            .select('id, full_name, email, role, site_location')
            .eq('organization_id', user.organizationId);
        final Map<String, Map<String, dynamic>> empMap = {};
        for (var emp in (empRes as List)) {
          empMap[emp['id'].toString()] = emp;
        }

        final list = (plainRes as List).map((json) {
          final emp = empMap[json['employee_id']?.toString()];
          return LeaveRequest.fromJson({
            ...json,
            'employees': ?emp,
          });
        }).toList();

        state = LeaveState(requests: list, isLoading: false);
      } catch (err) {
        state = state.copyWith(isLoading: false, error: err.toString());
      }
    }
  }

  Future<bool> createLeaveRequest({
    required String employeeId,
    required String leaveType,
    required DateTime startDate,
    required DateTime endDate,
    String? reason,
  }) async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return false;
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    if (end.isBefore(start)) throw Exception('The end date must be on or after the start date.');
    final overlapping = state.requests.any((r) =>
        r.employeeId == employeeId && !r.isDeclined && !r.startDate.isAfter(end) && !r.endDate.isBefore(start));
    if (overlapping) throw Exception('There is already a leave request covering these dates.');

    try {
      final insertData = {
        'organization_id': user.organizationId,
        'employee_id': employeeId,
        'leave_type': leaveType,
        'start_date': _dateOnly(start),
        'end_date': _dateOnly(end),
        'reason': reason == null || reason.trim().isEmpty ? null : reason.trim(),
        'status': 'pending',
      };

      await _supabase.from('leave_requests').insert(insertData);
      await loadLeaveRequests(silent: true);
      return true;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> updateStatus(String id, String status) async {
    try {
      await _supabase.from('leave_requests').update({'status': status}).eq('id', id);
      final updated = state.requests.map((r) {
        return r.id == id ? r.copyWith(status: status) : r;
      }).toList();
      state = state.copyWith(requests: updated);
      await loadLeaveRequests(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteLeaveRequest(String id) async {
    try {
      await _supabase.from('leave_requests').delete().eq('id', id);
      state = state.copyWith(requests: state.requests.where((r) => r.id != id).toList());
      await loadLeaveRequests(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _debounce?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}

final leaveStateProvider = StateNotifierProvider<LeaveNotifier, LeaveState>((ref) {
  // Rebuild (and re-subscribe) whenever the signed-in user changes.
  ref.watch(authProvider.select((s) => s.currentUser?.id));
  return LeaveNotifier(ref);
});

final leaveProvider = Provider<AsyncValue<List<LeaveRequest>>>((ref) {
  final leaveState = ref.watch(leaveStateProvider);
  if (leaveState.isLoading && leaveState.requests.isEmpty) {
    return const AsyncValue.loading();
  }
  if (leaveState.error != null && leaveState.requests.isEmpty) {
    return AsyncValue.error(leaveState.error!, StackTrace.current);
  }
  return AsyncValue.data(leaveState.requests);
});
