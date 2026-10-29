import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';

/// Everyone in the signed-in user's organization, kept live via Realtime.
final staffProvider = StreamProvider<List<Employee>>((ref) {
  final orgId = ref.watch(authProvider.select((s) => s.currentUser?.organizationId));
  if (orgId == null) return Stream.value(const []);
  return Supabase.instance.client
      .from('employees')
      .stream(primaryKey: ['id'])
      .eq('organization_id', orgId)
      .order('full_name', ascending: true)
      .map((rows) => rows.map(Employee.fromJson).toList());
});
