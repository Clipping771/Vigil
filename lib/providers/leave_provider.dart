import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/leave_request.dart';

final leaveProvider = FutureProvider<List<LeaveRequest>>((ref) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('leave_requests')
      .select()
      .order('start_date', ascending: false);
      
  return response.map((json) => LeaveRequest.fromJson(json)).toList();
});
