import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/geofence_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';
import '../models/geofence_zone.dart';

class GeofenceScreen extends ConsumerStatefulWidget {
  const GeofenceScreen({super.key});

  @override
  ConsumerState<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends ConsumerState<GeofenceScreen> {
  Future<void> _showAddZoneDialog() async {
    final nameController = TextEditingController();
    final latController = TextEditingController();
    final lngController = TextEditingController();
    final radiusController = TextEditingController(text: '100.0');

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text('Add Geofence Zone', style: GoogleFonts.outfit(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Zone Name', labelStyle: TextStyle(color: Colors.white54)),
                ),
                TextField(
                  controller: latController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Latitude', labelStyle: TextStyle(color: Colors.white54)),
                ),
                TextField(
                  controller: lngController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Longitude', labelStyle: TextStyle(color: Colors.white54)),
                ),
                TextField(
                  controller: radiusController,
                  style: const TextStyle(color: Colors.white),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Radius (meters)', labelStyle: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
              onPressed: () async {
                final user = ref.read(authProvider).currentUser;
                if (user == null) return;

                final name = nameController.text.trim();
                final lat = double.tryParse(latController.text.trim());
                final lng = double.tryParse(lngController.text.trim());
                final rad = double.tryParse(radiusController.text.trim());

                if (name.isEmpty || lat == null || lng == null || rad == null) {
                   ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all fields with valid numbers'), backgroundColor: Colors.red));
                   return;
                }

                try {
                  await Supabase.instance.client.from('geofence_zones').insert({
                    'organization_id': user.organizationId,
                    'name': name,
                    'latitude': lat,
                    'longitude': lng,
                    'radius_meters': rad,
                  });
                  ref.refresh(geofenceProvider);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Geofence zone added'), backgroundColor: Colors.green));
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error adding zone: $e'), backgroundColor: Colors.red));
                  }
                }
              },
              child: const Text('Add Zone'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteZone(String id) async {
    try {
      await Supabase.instance.client.from('geofence_zones').delete().eq('id', id);
      ref.refresh(geofenceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zone deleted'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error deleting zone: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final zonesAsync = ref.watch(geofenceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Geofence Zones', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => ref.refresh(geofenceProvider),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            icon: const Icon(Icons.add),
            label: const Text('New Zone'),
            onPressed: _showAddZoneDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Company Locations',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ).animate().fadeIn().slideY(begin: -0.2, end: 0),
            const SizedBox(height: 8),
            Text(
              'Manage authorized geofence zones where employees can clock in and out.',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2, end: 0),
            const SizedBox(height: 32),
            Expanded(
              child: zonesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
                data: (zones) {
                  if (zones.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.location_off, size: 64, color: Colors.white24).animate().scale(),
                          const SizedBox(height: 16),
                          Text('No geofence zones set up.', style: GoogleFonts.outfit(fontSize: 20, color: Colors.white54)),
                        ],
                      )
                    );
                  }
                  
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 24,
                      mainAxisSpacing: 24,
                      childAspectRatio: 1.5,
                    ),
                    itemCount: zones.length,
                    itemBuilder: (context, index) {
                      final zone = zones[index];
                      return _buildZoneCard(zone, index);
                    },
                  );
                }
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildZoneCard(GeofenceZone zone, int index) {
    return PremiumCard(
      blurRadius: 15,
      opacity: 0.05,
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  zone.name, 
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _deleteZone(zone.id),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.location_on, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Text('${zone.latitude.toStringAsFixed(8)}, ${zone.longitude.toStringAsFixed(8)}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.radar, size: 16, color: Colors.white54),
              const SizedBox(width: 8),
              Text('Radius: ${zone.radiusMeters}m', style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const Spacer(),
          Container(
             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
             decoration: BoxDecoration(
               color: Colors.green.withOpacity(0.1),
               borderRadius: BorderRadius.circular(8),
               border: Border.all(color: Colors.green.withOpacity(0.3)),
             ),
             child: const Row(
               mainAxisSize: MainAxisSize.min,
               children: [
                 Icon(Icons.check_circle, color: Colors.green, size: 14),
                 SizedBox(width: 8),
                 Text('Active Zone', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
               ],
             )
          )
        ],
      ),
    ).animate().fadeIn(delay: (50 * index).ms).scale(curve: Curves.easeOutBack, duration: 400.ms);
  }
}
