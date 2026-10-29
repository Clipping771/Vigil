import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/geofence_zone.dart';
import '../providers/auth_provider.dart';
import '../providers/geofence_provider.dart';
import '../widgets/ui_kit.dart';

class GeofenceScreen extends ConsumerStatefulWidget {
  const GeofenceScreen({super.key});

  @override
  ConsumerState<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends ConsumerState<GeofenceScreen> {
  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(geofenceProvider);
    return AppPage(
      title: 'Work sites',
      actions: [
        IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(geofenceProvider)),
      ],
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-site',
        onPressed: () => _editZone(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add site'),
      ),
      children: [
        const SectionHeader(
          'Geofenced work sites',
          subtitle: 'Staff are verified as on-site when they clock in inside one of these areas.',
          padding: EdgeInsets.only(top: 8, bottom: 16),
        ),
        zones.when(
          loading: () => const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
          error: (_, _) => Card(
            child: EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load work sites',
              action: OutlinedButton(onPressed: () => ref.invalidate(geofenceProvider), child: const Text('Try again')),
            ),
          ),
          data: (list) => list.isEmpty
              ? Card(
                  child: EmptyState(
                    icon: Icons.add_location_alt_outlined,
                    title: 'No work sites yet',
                    message: 'Add your first site so staff can verify their location when clocking in.',
                    action: FilledButton.icon(onPressed: () => _editZone(), icon: const Icon(Icons.add), label: const Text('Add site')),
                  ),
                )
              : ResponsiveGrid(
                  minItemWidth: 300,
                  children: [for (final z in list) _zoneCard(z)],
                ),
        ),
      ],
    );
  }

  Widget _zoneCard(GeofenceZone z) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.secondaryContainer,
                  child: Icon(Icons.location_on_outlined, color: cs.onSecondaryContainer),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(z.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  onSelected: (v) => switch (v) {
                    'edit' => _editZone(z),
                    'qr' => _showQr(z),
                    _ => _deleteZone(z),
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit site'))),
                    PopupMenuItem(value: 'qr', child: ListTile(leading: Icon(Icons.qr_code_2), title: Text('Show site QR code'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete site'))),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _detail(Icons.my_location, '${z.latitude.toStringAsFixed(5)}, ${z.longitude.toStringAsFixed(5)}'),
            const SizedBox(height: 6),
            _detail(Icons.radar, '${z.radiusMeters.toStringAsFixed(0)} m radius'),
            const SizedBox(height: 16),
            Row(
              children: [
                const StatusChip('Active', tone: Tone.success, icon: Icons.check_circle_outline),
                const Spacer(),
                TextButton.icon(onPressed: () => _showQr(z), icon: const Icon(Icons.qr_code_2, size: 18), label: const Text('QR code')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(IconData icon, String text) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
      ],
    );
  }

  void _showQr(GeofenceZone z) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(z.name),
        content: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: siteQrPayload(z.id), size: 232),
              ),
              const SizedBox(height: 16),
              Text(
                'Print this code and display it at the site. Staff scan it from the punch clock to clock in.',
                textAlign: TextAlign.center,
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
      ),
    );
  }

  Future<void> _deleteZone(GeofenceZone z) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete "${z.name}"?',
      message: 'Staff will no longer be verified at this site, and its QR code will stop working.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await Supabase.instance.client.from('geofence_zones').delete().eq('id', z.id);
      if (mounted) showMessage(context, 'Site deleted.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not delete the site. You may not have permission.');
    }
  }

  /// Adds a new work site, or edits [existing] when given.
  Future<void> _editZone([GeofenceZone? existing]) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: existing?.name);
    final lat = TextEditingController(text: existing?.latitude.toStringAsFixed(6));
    final lng = TextEditingController(text: existing?.longitude.toStringAsFixed(6));
    final radius = TextEditingController(text: existing?.radiusMeters.toStringAsFixed(0) ?? '100');
    var saving = false;
    var locating = false;

    String? number(String? v, double min, double max, String label) {
      final n = double.tryParse(v?.trim() ?? '');
      if (n == null) return 'Enter a number';
      if (n < min || n > max) return '$label must be between ${min.toStringAsFixed(0)} and ${max.toStringAsFixed(0)}';
      return null;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Add work site' : 'Edit work site'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Site name', hintText: 'e.g. Adelaide CBD'),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: locating
                          ? null
                          : () async {
                              setLocal(() => locating = true);
                              try {
                                var p = await Geolocator.checkPermission();
                                if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
                                if (p == LocationPermission.denied || p == LocationPermission.deniedForever) throw Exception();
                                final pos = await Geolocator.getCurrentPosition();
                                lat.text = pos.latitude.toStringAsFixed(6);
                                lng.text = pos.longitude.toStringAsFixed(6);
                              } catch (_) {
                                if (mounted) showMessage(this.context, 'Could not read your location.');
                              } finally {
                                setLocal(() => locating = false);
                              }
                            },
                      icon: locating
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.my_location, size: 18),
                      label: const Text('Use my current location'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: lat,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Latitude'),
                            validator: (v) => number(v, -90, 90, 'Latitude'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: lng,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(labelText: 'Longitude'),
                            validator: (v) => number(v, -180, 180, 'Longitude'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: radius,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Radius', suffixText: 'metres', helperText: 'How far from the centre still counts as on-site'),
                      validator: (v) => number(v, 10, 5000, 'Radius'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      final user = ref.read(authProvider).currentUser;
                      if (user == null) return;
                      setLocal(() => saving = true);
                      try {
                        final data = {
                          'name': name.text.trim(),
                          'latitude': double.parse(lat.text.trim()),
                          'longitude': double.parse(lng.text.trim()),
                          'radius_meters': double.parse(radius.text.trim()),
                        };
                        final table = Supabase.instance.client.from('geofence_zones');
                        if (existing == null) {
                          await table.insert({...data, 'organization_id': user.organizationId});
                        } else {
                          await table.update(data).eq('id', existing.id);
                        }
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (mounted) showMessage(this.context, existing == null ? 'Site added.' : 'Site updated.');
                      } catch (_) {
                        setLocal(() => saving = false);
                        if (mounted) showMessage(this.context, 'Could not save the site. You may not have permission.');
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(existing == null ? 'Add site' : 'Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, lat, lng, radius]) {
      c.dispose();
    }
  }
}
