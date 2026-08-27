import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class AdminDatabaseViewer extends ConsumerStatefulWidget {
  const AdminDatabaseViewer({super.key});

  @override
  ConsumerState<AdminDatabaseViewer> createState() => _AdminDatabaseViewerState();
}

class _AdminDatabaseViewerState extends ConsumerState<AdminDatabaseViewer> {
  final _supabase = Supabase.instance.client;
  
  final List<String> _tables = [
    'organizations',
    'employees',
    'shifts',
    'clock_events',
    'exceptions',
    'leave_requests'
  ];
  
  String _selectedTable = 'organizations';
  List<dynamic> _tableData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchTableData(_selectedTable);
  }

  Future<void> _fetchTableData(String table) async {
    setState(() {
      _selectedTable = table;
      _isLoading = true;
    });
    

    
    try {
      final response = await _supabase.from(table).select().limit(100);
      if (mounted) {
        setState(() {
          _tableData = response;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading $table: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Raw Database Viewer', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _selectedTable,
                items: _tables.map((t) => DropdownMenuItem(value: t, child: Text(t.toUpperCase()))).toList(),
                onChanged: (val) {
                  if (val != null) _fetchTableData(val);
                },
              )
            ],
          ),
          const SizedBox(height: 24),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : _buildDataGrid(),
          )
        ],
      ),
    );
  }

  Widget _buildDataGrid() {
    if (_tableData.isEmpty) {
      return const Center(child: Text('No data found in this table.'));
    }

    // Extract columns from the first row
    final columns = _tableData.first.keys.toList();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            columns: columns.map<DataColumn>((c) => DataColumn(label: Text(c.toString(), style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
            rows: _tableData.map<DataRow>((row) {
              return DataRow(
                cells: columns.map<DataCell>((col) => DataCell(Text(row[col]?.toString() ?? 'null'))).toList(),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
