import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift.dart';

import '../providers/auth_provider.dart';

final rosterProvider = FutureProvider<List<Shift>>((ref) async {
  final currentUser = ref.watch(authProvider).currentUser;
  if (currentUser == null) return [];

  final supabase = Supabase.instance.client;
  var query = supabase.from('shifts').select();

  if (currentUser.role == 'staff') {
    // Staff only see their own assigned roster shifts
    query = query.eq('employee_id', currentUser.id);
  } else if (currentUser.role != 'system_admin') {
    // Admin, Manager, and Owner see all shifts in their organization
    query = query.eq('organization_id', currentUser.organizationId);
  }

  final response = await query.order('start_time', ascending: true);
  return (response as List).map((json) => Shift.fromJson(json)).toList();
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

// A provider that returns the current employee's scheduled shift for today
final todayShiftProvider = FutureProvider<Shift?>((ref) async {
  final currentUser = ref.watch(authProvider).currentUser;
  if (currentUser == null) return null;

  final now = DateTime.now();
  final startOfDay = DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
  final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59).toUtc().toIso8601String();

  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('shifts')
      .select()
      .eq('employee_id', currentUser.id)
      .gte('start_time', startOfDay)
      .lte('start_time', endOfDay)
      .order('start_time', ascending: true)
      .limit(1);

  if ((response as List).isNotEmpty) {
    return Shift.fromJson(response.first);
  }
  return null;
});
