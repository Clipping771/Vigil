import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reporting_engine.dart';
import '../widgets/app_shell.dart';
import '../widgets/agent_fab.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  final _engine = ReportingEngine();
  late DateTimeRange _range = _defaultRange();
  late DateTimeRange _payPeriod = _defaultPayPeriod();
  String? _exporting; // 'csv' | 'pdf' | 'timesheet-csv' | 'timesheet-pdf'
  final _emailController = TextEditingController();

  /// The last full fortnight, so nobody's current shift is left open by default.
  /// Start and end are the first and last days of the period.
  static DateTimeRange _defaultPayPeriod() {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, now.day - 14), end: DateTime(now.year, now.month, now.day - 1));
  }

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
        final bytes = await _engine.buildPdf(rows, organizationName: await _organizationName(user.organizationId), period: _periodLabel);
        await _engine.savePdf(bytes, name);
      }
      messenger.showSnackBar(SnackBar(content: Text('Exported ${rows.length} exceptions as ${format.toUpperCase()}.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Future<String> _organizationName(String organizationId) async {
    final org = await Supabase.instance.client.from('organizations').select('name').eq('id', organizationId).maybeSingle();
    return org?['name'] ?? 'Organization';
  }

  String get _payPeriodLabel {
    final f = DateFormat('d MMM yyyy');
    return '${f.format(_payPeriod.start)} – ${f.format(_payPeriod.end)}';
  }

  Future<void> _pickPayPeriod() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _payPeriod,
      helpText: 'Select pay period',
    );
    if (picked != null) setState(() => _payPeriod = picked);
  }

  Future<void> _exportTimesheet(String format) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final first = _payPeriod.start, last = _payPeriod.end;
    setState(() => _exporting = 'timesheet-$format');
    try {
      final rows = await _engine.fetchTimesheet(
        user,
        from: DateTime(first.year, first.month, first.day),
        to: DateTime(last.year, last.month, last.day + 1),
      );
      final name = 'vigil-timesheet-${DateFormat('yyyyMMdd').format(first)}-${DateFormat('yyyyMMdd').format(last)}';
      if (format == 'csv') {
        await _engine.saveCsv(_engine.buildTimesheetCsv(rows, firstDay: first, lastDay: last), name);
      } else {
        final bytes = await _engine.buildTimesheetPdf(rows, organizationName: await _organizationName(user.organizationId), period: _payPeriodLabel);
        await _engine.savePdf(bytes, name);
      }
      final toReview = rows.where((r) => r.needsReview).length;
      messenger.showSnackBar(SnackBar(
        content: Text('Exported ${rows.length} employees as ${format.toUpperCase()}.'
            '${toReview > 0 ? ' $toReview need review before payroll.' : ''}'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = null);
    }
  }

  Widget _downloadButtons({required String prefix, required void Function(String format) onExport}) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        FilledButton.icon(
          onPressed: _exporting != null ? null : () => onExport('csv'),
          icon: _exporting == '${prefix}csv'
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.table_chart_outlined, size: 18),
          label: const Text('Download CSV'),
        ),
        ElevatedButton.icon(
          onPressed: _exporting != null ? null : () => onExport('pdf'),
          icon: _exporting == '${prefix}pdf'
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.picture_as_pdf_outlined, size: 18),
          label: const Text('Download PDF'),
        ),
      ],
    );
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
            _downloadButtons(prefix: '', onExport: _export),
          ],
        ),
      ),
    );

    final isManager = ref.watch(authProvider).currentUser?.isManager ?? false;
    final timesheetCard = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardTitle(icon: Icons.more_time, title: 'Export timesheets'),
            const SizedBox(height: 8),
            Text('Ordinary hours, overtime and breaks for each employee, to import into your payroll software. '
                'Anyone with open exceptions is flagged.',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _pickPayPeriod,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(_payPeriodLabel),
            ),
            const SizedBox(height: 16),
            _downloadButtons(prefix: 'timesheet-', onExport: _exportTimesheet),
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
              showSelectedIcon: false,
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
      appBar: AppBar(leading: ShellMenuButton.maybe(context), title: const Text('Reports'), actions: const [AiAssistantButton(), SizedBox(width: 8)]),
      body: ListView(
        padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 28),
        children: [
          const PageHeader(
            title: 'Compliance reports',
            subtitle: 'Export exception history and timesheets, and configure scheduled summaries.',
          ),
          const SizedBox(height: 24),
          LayoutBuilder(builder: (context, c) {
            if (c.maxWidth < 900) {
              return Column(children: [
                exportCard,
                const SizedBox(height: 16),
                if (isManager) ...[timesheetCard, const SizedBox(height: 16)],
                scheduleCard,
              ]);
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: exportCard),
                    const SizedBox(width: 20),
                    Expanded(child: isManager ? timesheetCard : scheduleCard),
                  ],
                ),
                if (isManager) ...[const SizedBox(height: 20), scheduleCard],
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
