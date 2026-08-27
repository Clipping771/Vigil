import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';

final staffProvider = FutureProvider<List<Employee>>((ref) async {
  final currentUser = ref.read(authProvider).currentUser;
  if (currentUser == null || currentUser.organizationId == null) return [];

  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('employees')
      .select()
      .eq('organization_id', currentUser.organizationId!)
      .order('full_name', ascending: true);
      
  return response.map((json) => Employee.fromJson(json)).toList();
});
