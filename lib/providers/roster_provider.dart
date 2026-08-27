import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/shift.dart';
import 'package:table_calendar/table_calendar.dart'; // for isSameDay

import '../providers/auth_provider.dart';

final rosterProvider = FutureProvider<List<Shift>>((ref) async {
  final currentUser = ref.read(authProvider).currentUser;
  if (currentUser == null || currentUser.organizationId == null) return [];

  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('shifts')
      .select()
      .eq('organization_id', currentUser.organizationId!)
      .order('start_time', ascending: true);
      
  return response.map((json) => Shift.fromJson(json)).toList();
});

// A provider that groups shifts by their Date (ignoring time) for the calendar UI
final shiftsByDayProvider = FutureProvider<Map<DateTime, List<Shift>>>((ref) async {
  final shifts = await ref.watch(rosterProvider.future);
  
  Map<DateTime, List<Shift>> grouped = {};
  
  for (var shift in shifts) {
    // Normalize the date to midnight to use as a dictionary key
    final normalizedDate = DateTime.utc(shift.startTime.year, shift.startTime.month, shift.startTime.day);
    
    if (grouped.containsKey(normalizedDate)) {
      grouped[normalizedDate]!.add(shift);
    } else {
      grouped[normalizedDate] = [shift];
    }
  }
  
  return grouped;
});
