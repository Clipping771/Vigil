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

  LeaveNotifier(this._ref) : super(LeaveState(isLoading: true)) {
    loadLeaveRequests();
    _setupRealtime();
  }

  void _setupRealtime() {
    try {
      _realtimeChannel = _supabase.channel('public_leave_requests_feed')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'leave_requests',
          callback: (_) {
            loadLeaveRequests(silent: true);
          },
        )
        ..subscribe();
    } catch (_) {
      // Realtime channel fail-safe
    }
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
      var query = _supabase.from('leave_requests').select('*, employees(full_name, email, role, site_location)');

      if (user.role != 'system_admin') {
        query = query.eq('organization_id', user.organizationId);
      }

      final response = await query.order('start_date', ascending: false);
      
      final list = (response as List).map((json) => LeaveRequest.fromJson(json)).toList();
      state = LeaveState(requests: list, isLoading: false);
    } catch (e) {
      // Fallback: If Supabase foreign key join encounters an issue, fetch employees separately
      try {
        var plainQuery = _supabase.from('leave_requests').select();
        if (user.role != 'system_admin') {
          plainQuery = plainQuery.eq('organization_id', user.organizationId);
        }
        final plainRes = await plainQuery.order('start_date', ascending: false);
        
        final empRes = await _supabase.from('employees').select('id, full_name, email, role, site_location');
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

    try {
      final insertData = {
        'organization_id': user.organizationId,
        'employee_id': employeeId,
        'leave_type': leaveType,
        'start_date': startDate.toIso8601String().substring(0, 10),
        'end_date': endDate.toIso8601String().substring(0, 10),
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

  @override
  void dispose() {
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
