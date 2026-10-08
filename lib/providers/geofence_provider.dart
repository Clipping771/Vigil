import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/geofence_zone.dart';

final geofenceProvider = FutureProvider<List<GeofenceZone>>((ref) async {
  final supabase = Supabase.instance.client;
  final response = await supabase
      .from('geofence_zones')
      .select()
      .order('created_at', ascending: false);
      
  return response.map((json) => GeofenceZone.fromJson(json)).toList();
});
