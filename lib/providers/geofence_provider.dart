import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/geofence_zone.dart';
import 'auth_provider.dart';
import 'realtime_rows.dart';

/// The organization's work sites, kept live via Supabase Realtime.
final geofenceProvider = StreamProvider<List<GeofenceZone>>((ref) {
  final orgId = ref.watch(authProvider.select((s) => s.currentUser?.organizationId));
  if (orgId == null) return Stream.value(const []);
  final clean = liveRows(ref, 'geofence_zones');
  return Supabase.instance.client
      .from('geofence_zones')
      .stream(primaryKey: ['id'])
      .eq('organization_id', orgId)
      .order('created_at', ascending: false)
      .map((rows) => clean(rows).map(GeofenceZone.fromJson).toList());
});
