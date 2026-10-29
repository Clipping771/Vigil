import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/exception_record.dart';
import '../models/clock_event.dart';
import '../models/shift.dart';
import '../models/leave_request.dart';
import '../services/exception_engine.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

class ExceptionState {
  final List<ExceptionRecord> allExceptions;
  final bool isLoading;
  final String? error;

  ExceptionState({
    this.allExceptions = const [],
    this.isLoading = false,
    this.error,
  });

  List<ExceptionRecord> get activeExceptions =>
      allExceptions.where((e) => !e.isResolved && !e.isIgnored).toList();

  List<ExceptionRecord> get pendingExceptions =>
      allExceptions.where((e) => e.isPending).toList();

  List<ExceptionRecord> get resolvedExceptions =>
      allExceptions.where((e) => e.isResolved).toList();

  int get activeCount => activeExceptions.length;
  int get pendingCount => pendingExceptions.length;
  int get criticalCount => allExceptions.where((e) => e.isCritical && (e.isPending || e.isAcknowledged)).length;
  int get highCount => allExceptions.where((e) => e.isHigh && (e.isPending || e.isAcknowledged)).length;
  int get resolvedCount => resolvedExceptions.length;
  int get acknowledgedCount => allExceptions.where((e) => e.isAcknowledged).length;

  ExceptionState copyWith({
    List<ExceptionRecord>? allExceptions,
    bool? isLoading,
    String? error,
  }) {
    return ExceptionState(
      allExceptions: allExceptions ?? this.allExceptions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class ExceptionNotifier extends StateNotifier<ExceptionState> {
  final Ref _ref;
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;

  ExceptionNotifier(this._ref) : super(ExceptionState(isLoading: true)) {
    fetchExceptions();
    _setupRealtime();
  }

  void _setupRealtime() {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return;
    _subscription = _supabase.channel('exception_records_${user.organizationId}')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'exception_records',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'organization_id',
          value: user.organizationId,
        ),
        callback: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 400), () {
            if (mounted) fetchExceptions(silent: true);
          });
        },
      )
      ..subscribe();
  }

  Timer? _debounce;

  Future<void> fetchExceptions({bool silent = false}) async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) {
      state = ExceptionState(allExceptions: [], isLoading: false);
      return;
    }

    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    try {
      // 1. Fetch with joined employee details
      final response = await _supabase
          .from('exception_records')
          .select('*, employees(full_name, email, role, site_location)')
          .eq('organization_id', user.organizationId)
          .order('created_at', ascending: false);
      final list = (response as List).map((json) => ExceptionRecord.fromJson(json)).toList();
      state = ExceptionState(allExceptions: list, isLoading: false);
    } catch (e) {
      // Fallback: If foreign join is not supported, query plain and map employee details
      try {
        final plainRes = await _supabase
            .from('exception_records')
            .select()
            .eq('organization_id', user.organizationId)
            .order('created_at', ascending: false);

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
          return ExceptionRecord.fromJson({
            ...json,
            'employees': ?emp,
          });
        }).toList();

        state = ExceptionState(allExceptions: list, isLoading: false);
      } catch (err) {
        state = state.copyWith(isLoading: false, error: err.toString());
      }
    }
  }

  Future<void> resolveException(String id, {String? resolutionNote}) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase.from('exception_records').update({
        'status': 'resolved',
        'resolved_at': now,
        'resolution_note': ?resolutionNote,
      }).eq('id', id);

      // Optimistic update
      final updated = state.allExceptions.map((ex) {
        return ex.id == id
            ? ex.copyWith(
                status: 'resolved',
                resolvedAt: DateTime.parse(now),
              )
            : ex;
      }).toList();
      state = state.copyWith(allExceptions: updated);

      await fetchExceptions(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> acknowledgeException(String id) async {
    try {
      await _supabase.from('exception_records').update({
        'status': 'acknowledged',
      }).eq('id', id);

      final updated = state.allExceptions.map((ex) {
        return ex.id == id ? ex.copyWith(status: 'acknowledged') : ex;
      }).toList();
      state = state.copyWith(allExceptions: updated);

      await fetchExceptions(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> ignoreException(String id, {String? reason}) async {
    try {
      await _supabase.from('exception_records').update({
        'status': 'ignored',
        'resolution_note': ?reason,
      }).eq('id', id);

      final updated = state.allExceptions.map((ex) {
        return ex.id == id ? ex.copyWith(status: 'ignored') : ex;
      }).toList();
      state = state.copyWith(allExceptions: updated);

      await fetchExceptions(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> batchResolve(List<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final now = DateTime.now().toIso8601String();
      await _supabase
          .from('exception_records')
          .update({'status': 'resolved', 'resolved_at': now})
          .filter('id', 'in', ids);

      await fetchExceptions(silent: true);
    } catch (e) {
      rethrow;
    }
  }

  /// Runs an automated Fair Work compliance audit scan across current rosters,
  /// clock events, and leaves, persisting any detected violations.
  Future<int> runComplianceScan() async {
    final user = _ref.read(authProvider).currentUser;
    if (user == null) return 0;

    final orgId = user.organizationId;

    try {
      final now = DateTime.now();
      final todayStartLocal = DateTime(now.year, now.month, now.day);
      final settings = _ref.read(settingsProvider);

      // 1. Fetch yesterday's and today's shifts (yesterday is needed for rest-gap checks)
      final shiftsRes = await _supabase
          .from('shifts')
          .select()
          .eq('organization_id', orgId)
          .gte('start_time', todayStartLocal.subtract(const Duration(days: 1)).toUtc().toIso8601String())
          .lt('start_time', todayStartLocal.add(const Duration(days: 1)).toUtc().toIso8601String());
      final allShifts = (shiftsRes as List).map((s) => Shift.fromJson(s)).toList();
      final shifts = allShifts.where((s) => !s.startTime.toLocal().isBefore(todayStartLocal)).toList();

      // 2. Fetch clock events since yesterday (covers overnight shifts)
      final eventsRes = await _supabase
          .from('clock_events')
          .select()
          .eq('organization_id', orgId)
          .gte('event_time', todayStartLocal.subtract(const Duration(days: 1)).toUtc().toIso8601String());
      final events = (eventsRes as List).map((e) => ClockEvent.fromJson(e)).toList();

      // 3. Fetch active leaves
      final leavesRes = await _supabase
          .from('leave_requests')
          .select()
          .eq('organization_id', orgId)
          .eq('status', 'approved');
      final leaves = (leavesRes as List).map((l) => LeaveRequest.fromJson(l)).toList();

      // 4. Run detection engines
      final missedPunches = ExceptionEngine.detectMissedPunches(
        shifts: allShifts.where((s) => s.startTime.isBefore(now)).toList(),
        events: events,
        graceMinutes: settings.allowedLateMinutes,
        overtimeMinutes: settings.allowedOvertimeMinutes,
        organizationId: orgId,
      );

      final leaveConflicts = ExceptionEngine.detectLeaveConflicts(
        upcomingShifts: shifts,
        approvedLeave: leaves,
        organizationId: orgId,
      );

      final restBreaches = ExceptionEngine.detectRestBreaches(
        upcomingShifts: shifts,
        pastShifts: allShifts,
        organizationId: orgId,
      );

      final allDetected = [...missedPunches, ...leaveConflicts, ...restBreaches];
      int insertedCount = 0;

      for (var detected in allDetected) {
        // Prevent duplicate insertions for the same employee, shift, and exception_type
        final existing = state.allExceptions.any((existing) =>
            existing.employeeId == detected.employeeId &&
            existing.exceptionType == detected.exceptionType &&
            existing.shiftId == detected.shiftId);

        if (!existing) {
          await _supabase.from('exception_records').insert({
            'organization_id': orgId,
            'employee_id': detected.employeeId,
            'exception_type': detected.exceptionType,
            'severity': detected.severity,
            'shift_id': detected.shiftId,
            'status': 'pending',
            'description': detected.description,
          });
          insertedCount++;
        }
      }

      await fetchExceptions(silent: true);
      return insertedCount;
    } catch (e) {
      debugPrint('Compliance scan failed: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _subscription?.unsubscribe();
    super.dispose();
  }
}

final exceptionStateProvider = StateNotifierProvider<ExceptionNotifier, ExceptionState>((ref) {
  // Rebuild (and re-subscribe) whenever the signed-in user changes.
  ref.watch(authProvider.select((s) => s.currentUser?.id));
  return ExceptionNotifier(ref);
});

// Backward-compatible AsyncValue providers
final exceptionStreamProvider = Provider<AsyncValue<List<ExceptionRecord>>>((ref) {
  final exState = ref.watch(exceptionStateProvider);
  if (exState.isLoading && exState.allExceptions.isEmpty) {
    return const AsyncValue.loading();
  }
  if (exState.error != null && exState.allExceptions.isEmpty) {
    return AsyncValue.error(exState.error!, StackTrace.current);
  }
  return AsyncValue.data(exState.allExceptions);
});

final activeExceptionsProvider = Provider<AsyncValue<List<ExceptionRecord>>>((ref) {
  final exState = ref.watch(exceptionStateProvider);
  if (exState.isLoading && exState.allExceptions.isEmpty) {
    return const AsyncValue.loading();
  }
  if (exState.error != null && exState.allExceptions.isEmpty) {
    return AsyncValue.error(exState.error!, StackTrace.current);
  }
  return AsyncValue.data(exState.activeExceptions);
});

class ExceptionService {
  final Ref _ref;

  ExceptionService(this._ref);

  Future<void> resolveException(String id, {String? resolutionNote}) async {
    await _ref.read(exceptionStateProvider.notifier).resolveException(id, resolutionNote: resolutionNote);
  }

  Future<void> acknowledgeException(String id) async {
    await _ref.read(exceptionStateProvider.notifier).acknowledgeException(id);
  }

  Future<void> ignoreException(String id, {String? reason}) async {
    await _ref.read(exceptionStateProvider.notifier).ignoreException(id, reason: reason);
  }

  Future<int> runComplianceScan() async {
    return await _ref.read(exceptionStateProvider.notifier).runComplianceScan();
  }
}

final exceptionServiceProvider = Provider<ExceptionService>((ref) {
  return ExceptionService(ref);
});
