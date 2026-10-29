import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/geofence_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';
import '../widgets/app_shell.dart';
import '../theme/ui.dart';
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
          backgroundColor: context.surfaceHigh,
          title: Text('Add Geofence Zone', style: GoogleFonts.outfit(color: context.fg())),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: TextStyle(color: context.fg()),
                  decoration: InputDecoration(labelText: 'Zone Name', labelStyle: TextStyle(color: context.fg(0.54))),
                ),
                TextField(
                  controller: latController,
                  style: TextStyle(color: context.fg()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Latitude', labelStyle: TextStyle(color: context.fg(0.54))),
                ),
                TextField(
                  controller: lngController,
                  style: TextStyle(color: context.fg()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Longitude', labelStyle: TextStyle(color: context.fg(0.54))),
                ),
                TextField(
                  controller: radiusController,
                  style: TextStyle(color: context.fg()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: 'Radius (meters)', labelStyle: TextStyle(color: context.fg(0.54))),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Use my current location'),
                    onPressed: () async {
                      try {
                        var permission = await Geolocator.checkPermission();
                        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
                        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
                          throw Exception('Location permission denied');
                        }
                        final pos = await Geolocator.getCurrentPosition();
                        latController.text = pos.latitude.toStringAsFixed(6);
                        lngController.text = pos.longitude.toStringAsFixed(6);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not read your location.')));
                        }
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: TextStyle(color: context.fg(0.54))),
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

                if (name.isEmpty || lat == null || lng == null || rad == null ||
                    lat.abs() > 90 || lng.abs() > 180 || rad < 10 || rad > 5000) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Enter a name, a valid latitude (−90…90), longitude (−180…180) and a radius of 10–5000 m.')));
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
                  ref.invalidate(geofenceProvider);
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

  Future<void> _deleteZone(GeofenceZone zone) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete zone?'),
        content: Text('Staff will no longer be able to verify clock-ins at "${zone.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = zone.id;
    try {
      await Supabase.instance.client.from('geofence_zones').delete().eq('id', id);
      ref.invalidate(geofenceProvider);
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
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text('Geofence Zones', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.fg())),
        leading: ShellMenuButton.maybe(context),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: context.fg(0.7)),
            onPressed: () => ref.invalidate(geofenceProvider),
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
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: context.fg()),
            ).animate().fadeIn().slideY(begin: -0.2, end: 0),
            const SizedBox(height: 8),
            Text(
              'Manage authorized geofence zones where employees can clock in and out.',
              style: TextStyle(color: context.fg().withValues(alpha: 0.6)),
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
                          Icon(Icons.location_off, size: 64, color: context.fg(0.24)).animate().scale(),
                          const SizedBox(height: 16),
                          Text('No geofence zones set up.', style: GoogleFonts.outfit(fontSize: 20, color: context.fg(0.54))),
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

  void _showSiteQr(GeofenceZone zone) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(zone.name),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: siteQrPayload(zone.id), size: 240),
              ),
              const SizedBox(height: 12),
              Text('Print and display this code at the site. Staff scan it from the punch clock to verify their clock-in.',
                  textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodySmall),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
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
                  style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.fg()),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Site QR code',
                icon: const Icon(Icons.qr_code_2),
                onPressed: () => _showSiteQr(zone),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                tooltip: 'Delete zone',
                onPressed: () => _deleteZone(zone),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.location_on, size: 16, color: context.fg(0.54)),
              const SizedBox(width: 8),
              Text('${zone.latitude.toStringAsFixed(8)}, ${zone.longitude.toStringAsFixed(8)}', style: TextStyle(color: context.fg(0.7))),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.radar, size: 16, color: context.fg(0.54)),
              const SizedBox(width: 8),
              Text('Radius: ${zone.radiusMeters}m', style: TextStyle(color: context.fg(0.7))),
            ],
          ),
          const Spacer(),
          Container(
             padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
             decoration: BoxDecoration(
               color: Colors.green.withValues(alpha: 0.1),
               borderRadius: BorderRadius.circular(8),
               border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
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
