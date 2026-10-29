import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift.dart';

import '../providers/auth_provider.dart';

/// Rostered shifts, kept live via Supabase Realtime. Managers see the whole
/// organization; staff see only their own shifts.
final rosterProvider = StreamProvider<List<Shift>>((ref) {
  final user = ref.watch(authProvider).currentUser;
  if (user == null) return Stream.value(const []);
  // Realtime streams accept a single filter, so narrow staff rosters here.
  return Supabase.instance.client
      .from('shifts')
      .stream(primaryKey: ['id'])
      .eq('organization_id', user.organizationId)
      .order('start_time', ascending: true)
      .map((rows) => rows
          .map(Shift.fromJson)
          .where((s) => user.isManager || s.employeeId == user.id)
          .toList());
});

// A provider that groups shifts by their Date (ignoring time) for the calendar UI
final shiftsByDayProvider = FutureProvider<Map<DateTime, List<Shift>>>((ref) async {
  final shifts = await ref.watch(rosterProvider.future);
  
  Map<DateTime, List<Shift>> grouped = {};
  
  for (var shift in shifts) {
    // Convert UTC time from DB to local time before extracting the calendar day
    final localStartTime = shift.startTime.toLocal();
    
    // Normalize the date to midnight to use as a dictionary key
    final normalizedDate = DateTime.utc(localStartTime.year, localStartTime.month, localStartTime.day);
    
    if (grouped.containsKey(normalizedDate)) {
      grouped[normalizedDate]!.add(shift);
    } else {
      grouped[normalizedDate] = [shift];
    }
  }
  
  return grouped;
});

/// The signed-in employee's first rostered shift today (derived from the
/// live roster, so it updates when a manager adds or removes a shift).
final todayShiftProvider = FutureProvider<Shift?>((ref) async {
  final user = ref.watch(authProvider).currentUser;
  if (user == null) return null;
  final shifts = await ref.watch(rosterProvider.future);
  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));
  final mine = shifts.where((s) {
    final start = s.startTime.toLocal();
    return s.employeeId == user.id && !start.isBefore(startOfDay) && start.isBefore(endOfDay);
  }).toList()
    ..sort((a, b) => a.startTime.compareTo(b.startTime));
  return mine.firstOrNull;
});
