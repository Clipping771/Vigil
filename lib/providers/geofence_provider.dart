import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/geofence_zone.dart';
import 'auth_provider.dart';

final geofenceProvider = FutureProvider<List<GeofenceZone>>((ref) async {
  final currentUser = ref.watch(authProvider).currentUser;
  if (currentUser == null) return [];
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('geofence_zones')
      .select()
      .eq('organization_id', currentUser.organizationId)
      .order('created_at', ascending: false);
      
  return response.map((json) => GeofenceZone.fromJson(json)).toList();
});
