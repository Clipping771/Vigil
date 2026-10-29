import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/geofence_zone.dart';
import 'auth_provider.dart';

/// The organization's work sites, kept live via Supabase Realtime.
final geofenceProvider = StreamProvider<List<GeofenceZone>>((ref) {
  final orgId = ref.watch(authProvider.select((s) => s.currentUser?.organizationId));
  if (orgId == null) return Stream.value(const []);
  return Supabase.instance.client
      .from('geofence_zones')
      .stream(primaryKey: ['id'])
      .eq('organization_id', orgId)
      .order('created_at', ascending: false)
      .map((rows) => rows.map(GeofenceZone.fromJson).toList());
});
