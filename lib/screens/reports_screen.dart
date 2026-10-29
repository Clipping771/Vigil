import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reporting_engine.dart';
import '../widgets/app_shell.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _engine = ReportingEngine();
  late DateTimeRange _range = _defaultRange();
  String? _exporting; // 'csv' | 'pdf'
  final _emailController = TextEditingController();

  static DateTimeRange _defaultRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return DateTimeRange(start: end.subtract(const Duration(days: 30)), end: end);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String get _periodLabel {
    final f = DateFormat('d MMM yyyy');
    return '${f.format(_range.start)} – ${f.format(_range.end.subtract(const Duration(days: 1)))}';
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _range.start, end: _range.end.subtract(const Duration(days: 1))),
    );
    if (picked != null) {
      setState(() => _range = DateTimeRange(start: picked.start, end: picked.end.add(const Duration(days: 1))));
    }
  }

  Future<void> _export(String format) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = format);
    try {
      final rows = await _engine.fetchExceptions(user.organizationId, from: _range.start, to: _range.end);
      final name = 'vigil-compliance-${DateFormat('yyyyMMdd').format(_range.start)}-'
          '${DateFormat('yyyyMMdd').format(_range.end.subtract(const Duration(days: 1)))}';
      if (format == 'csv') {
        await _engine.saveCsv(_engine.buildCsv(rows), name);
      } else {
        final org = await Supabase.instance.client
            .from('organizations')
            .select('name')
            .eq('id', user.organizationId)
            .maybeSingle();
        final bytes = await _engine.buildPdf(rows, organizationName: org?['name'] ?? 'Organization', period: _periodLabel);
        await _engine.savePdf(bytes, name);
      }
      messenger.showSnackBar(SnackBar(content: Text('Exported ${rows.length} exceptions as ${format.toUpperCase()}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not save. You may not have permission.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    if (_emailController.text.isEmpty && (settings.deliveryEmail ?? '').isNotEmpty) {
      _emailController.text = settings.deliveryEmail!;
    }

    final exportCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(icon: Icons.file_download_outlined, title: 'Export exceptions'),
            const SizedBox(height: 8),
            Text('Download every compliance exception in the selected period for payroll or audit.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _pickRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_periodLabel),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: _exporting != null ? null : () => _export('csv'),
                  icon: _exporting == 'csv'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('Download CSV'),
                ),
                ElevatedButton.icon(
                  onPressed: _exporting != null ? null : () => _export('pdf'),
                  icon: _exporting == 'pdf'
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Download PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final scheduleCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _CardTitle(icon: Icons.schedule_outlined, title: 'Scheduled delivery')),
                if (settings.isSaving)
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                Switch(
                  value: settings.autoReportingEnabled,
                  onChanged: (v) => _save(() => notifier.toggleAutoReporting(v)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Send a compliance summary to a manager or HR inbox on a schedule. '
              'Requires the Vigil reporting job to be deployed on your backend.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            Text('FREQUENCY', style: theme.textTheme.labelSmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Daily', label: Text('Daily')),
                ButtonSegment(value: 'Weekly', label: Text('Weekly')),
                ButtonSegment(value: 'Monthly', label: Text('Monthly')),
              ],
              selected: {settings.reportFrequency},
              onSelectionChanged: settings.autoReportingEnabled
                  ? (v) => _save(() => notifier.updateReportFrequency(v.first))
                  : null,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _emailController,
              enabled: settings.autoReportingEnabled,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Delivery email',
                prefixIcon: const Icon(Icons.mail_outline),
                suffixIcon: IconButton(
                  tooltip: 'Save email',
                  icon: const Icon(Icons.check),
                  onPressed: () {
                    final messenger = ScaffoldMessenger.of(context);
                    _save(() async {
                      await notifier.updateDeliveryEmail(_emailController.text);
                      messenger.showSnackBar(const SnackBar(content: Text('Delivery email saved.')));
                    });
                  },
                ),
              ),
              onSubmitted: (v) => _save(() => notifier.updateDeliveryEmail(v)),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(leading: ShellMenuButton.maybe(context), title: const Text('Reports')),
      body: ListView(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 28),
        children: [
          const PageHeader(
            title: 'Compliance reports',
            subtitle: 'Export exception history and configure scheduled summaries.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 900) {
              return Column(children: [exportCard, const SizedBox(height: 16), scheduleCard]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: exportCard),
                const SizedBox(width: 20),
                Expanded(child: scheduleCard),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _CardTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const _CardTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: scheme.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Flexible(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
      ],
    );
  }
}
