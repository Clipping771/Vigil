import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/ui_kit.dart';

const _tables = [
  'organizations',
  'organization_settings',
  'employees',
  'shifts',
  'clock_events',
  'breaks',
  'exception_records',
  'leave_requests',
  'geofence_zones',
  'audit_logs',
];

/// Read-only browser of the most recent rows in each table (system admins).
class AdminDatabaseViewer extends ConsumerStatefulWidget {
  const AdminDatabaseViewer({super.key});

  @override
  ConsumerState<AdminDatabaseViewer> createState() => _AdminDatabaseViewerState();
}

class _AdminDatabaseViewerState extends ConsumerState<AdminDatabaseViewer> {
  final _db = Supabase.instance.client;
  String _table = _tables.first;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load(_table);
  }

  Future<void> _load(String table) async {
    setState(() {
      _table = table;
      _loading = true;
      _failed = false;
    });
    try {
      final res = await _db.from(table).select().limit(100);
      if (mounted) setState(() => _rows = List<Map<String, dynamic>>.from(res));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pad = isCompact(context) ? 16.0 : 32.0;

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 32),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in _tables)
              ChoiceChip(
                label: Text(name),
                selected: _table == name,
                onSelected: (_) => _load(name),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Showing up to 100 rows · read-only', style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
        else if (_failed)
          Card(child: EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load $_table', action: OutlinedButton(onPressed: () => _load(_table), child: const Text('Try again'))))
        else if (_rows.isEmpty)
          const Card(child: EmptyState(icon: Icons.table_rows_outlined, title: 'This table is empty'))
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingTextStyle: t.labelLarge,
                dataTextStyle: t.bodySmall,
                columns: [for (final c in _rows.first.keys) DataColumn(label: Text(c))],
                rows: [
                  for (final row in _rows)
                    DataRow(cells: [
                      for (final c in _rows.first.keys)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: Text(row[c]?.toString() ?? '—', maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                    ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
