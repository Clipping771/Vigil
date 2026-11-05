import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/clock_event.dart';
import '../models/employee.dart';
import '../models/exception_record.dart';
import '../models/shift.dart';
import '../providers/auth_provider.dart';
import 'timesheet_calculator.dart';

/// Builds compliance exports (CSV / PDF) from the organization's exceptions,
/// and timesheet exports of the hours payroll software needs.
class ReportingEngine {
  SupabaseClient get _supabase => Supabase.instance.client;
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');
  static final _dayFmt = DateFormat('yyyy-MM-dd');

  /// How far either side of a pay period to read punches and breaks, so that
  /// overnight shifts crossing the period boundary still pair up.
  static const _punchWindow = Duration(days: 3);

  /// Every row of a query. The database returns at most 1000 rows per request,
  /// and a timesheet missing rows would silently understate someone's hours.
  /// [query] must have a stable order.
  Future<List<Map<String, dynamic>>> _allRows(
    PostgrestTransformBuilder<List<Map<String, dynamic>>> Function() query,
  ) async {
    const pageSize = 1000;
    final all = <Map<String, dynamic>>[];
    while (true) {
      final page = await query().range(all.length, all.length + pageSize - 1);
      if (page.isEmpty) return all;
      all.addAll(page);
    }
  }

  /// Hours for every employee of [requester]'s organization in a pay period
  /// ([from] inclusive, [to] exclusive). Managers only.
  Future<List<TimesheetRow>> fetchTimesheet(Employee requester, {required DateTime from, required DateTime to}) async {
    if (!requester.isManager) {
      throw StateError('Only managers can export timesheets.');
    }
    final org = requester.organizationId;
    final windowStart = from.subtract(_punchWindow).toUtc().toIso8601String();
    final windowEnd = to.add(_punchWindow).toUtc().toIso8601String();

    final results = await Future.wait([
      _allRows(() => _supabase.from('employees').select().eq('organization_id', org).order('id', ascending: true)),
      _allRows(() => _supabase
          .from('clock_events')
          .select()
          .eq('organization_id', org)
          .gte('event_time', windowStart)
          .lt('event_time', windowEnd)
          .order('event_time', ascending: true)
          .order('id', ascending: true)),
      _allRows(() => _supabase
          .from('breaks')
          .select()
          .eq('organization_id', org)
          .gte('start_time', windowStart)
          .lt('start_time', windowEnd)
          .order('start_time', ascending: true)
          .order('id', ascending: true)),
      _allRows(() => _supabase
          .from('shifts')
          .select()
          .eq('organization_id', org)
          .gte('end_time', from.subtract(_punchWindow + shiftMatchWindow).toUtc().toIso8601String())
          .lt('start_time', to.add(_punchWindow + shiftMatchWindow).toUtc().toIso8601String())
          .order('start_time', ascending: true)
          .order('id', ascending: true)),
      _allRows(() => _supabase
          .from('exception_records')
          .select()
          .eq('organization_id', org)
          .inFilter('status', ['pending', 'acknowledged'])
          .order('id', ascending: true)),
    ]);
    final settings = await _supabase
        .from('organization_settings')
        .select('allowed_overtime_minutes')
        .eq('organization_id', org)
        .maybeSingle();

    return TimesheetCalculator.calculate(
      employees: results[0].map(Employee.fromJson).toList(),
      events: results[1].map(ClockEvent.fromJson).toList(),
      breaks: results[2],
      shifts: results[3].map(Shift.fromJson).toList(),
      exceptions: results[4].map(ExceptionRecord.fromJson).toList(),
      // 30 is the column's default, for an organization with no settings row.
      allowedOvertimeMinutes: (settings?['allowed_overtime_minutes'] as num?)?.toInt() ?? 30,
      from: from,
      to: to,
    );
  }

  String _toCsv(List<List<Object?>> rows) {
    String cell(Object? v) {
      var s = (v ?? '').toString();
      // Neutralise spreadsheet formula injection.
      if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    return rows.map((r) => r.map(cell).join(',')).join('\r\n');
  }

  /// One row per employee. [firstDay] and [lastDay] are the period's dates.
  String buildTimesheetCsv(List<TimesheetRow> rows, {required DateTime firstDay, required DateTime lastDay}) => _toCsv([
        [
          'Period start', 'Period end', 'Employee', 'Email', 'Site', 'Ordinary hours', 'Overtime hours', 'Break hours',
          'Open exceptions', 'Needs review', 'Notes',
        ],
        for (final r in rows)
          [
            _dayFmt.format(firstDay),
            _dayFmt.format(lastDay),
            r.employee.fullName,
            r.employee.email,
            r.employee.siteLocation ?? '',
            formatHours(r.ordinary),
            formatHours(r.overtime),
            formatHours(r.breaks),
            r.openExceptions,
            r.needsReview ? 'Yes' : 'No',
            r.notes.join('; '),
          ],
      ]);

  Future<Uint8List> buildTimesheetPdf(List<TimesheetRow> rows, {required String organizationName, required String period}) async {
    final doc = pw.Document(
      title: 'Vigil timesheet',
      author: 'Vigil',
      theme: await (_pdfTheme ??= _loadPdfTheme()),
    );
    final ordinary = rows.fold(Duration.zero, (total, r) => total + r.ordinary);
    final overtime = rows.fold(Duration.zero, (total, r) => total + r.overtime);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _pdfHeader('Timesheet', organizationName),
        footer: _pdfFooter,
        build: (ctx) => [
          pw.SizedBox(height: 12),
          pw.Text('Pay period: $period', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
          pw.Text(
            'Employees: ${rows.length}   ·   Ordinary: ${formatHours(ordinary)}h   ·   Overtime: ${formatHours(overtime)}h   ·   '
            'To review: ${rows.where((r) => r.needsReview).length}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          if (rows.isEmpty)
            pw.Text('There are no employees to report.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Employee', 'Site', 'Ordinary hours', 'Overtime hours', 'Break hours', 'Open exceptions', 'Notes'],
              data: [
                for (final r in rows)
                  [
                    r.employee.fullName,
                    r.employee.siteLocation ?? '—',
                    formatHours(r.ordinary),
                    formatHours(r.overtime),
                    formatHours(r.breaks),
                    r.openExceptions > 0 ? '${r.openExceptions} open' : '—',
                    r.notes.join('; '),
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {
                for (var i = 0; i < 7; i++) i: i >= 2 && i <= 4 ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(120),
                1: const pw.FixedColumnWidth(110),
                2: const pw.FixedColumnWidth(55),
                3: const pw.FixedColumnWidth(55),
                4: const pw.FixedColumnWidth(50),
                5: const pw.FixedColumnWidth(60),
                6: const pw.FlexColumnWidth(),
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            'Hours are decimal. A shift is counted in the period it starts in, with breaks deducted. '
            'Overtime is time past the rostered shift end once it exceeds the organization\'s allowance.',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfHeader(String title, String organizationName) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('Vigil · $title', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
          pw.Text(organizationName, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
        ],
      );

  pw.Widget _pdfFooter(pw.Context ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Generated ${_dateFmt.format(DateTime.now())} · Page ${ctx.pageNumber}/${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
      );

  Future<List<ExceptionRecord>> fetchExceptions(
    String organizationId, {
    DateTime? from,
    DateTime? to,
  }) async {
    Future<List<ExceptionRecord>> run(String columns) async {
      var query = _supabase.from('exception_records').select(columns).eq('organization_id', organizationId);
      if (from != null) query = query.gte('created_at', from.toUtc().toIso8601String());
      if (to != null) query = query.lt('created_at', to.toUtc().toIso8601String());
      final response = await query.order('created_at', ascending: false);
      return response.map((json) => ExceptionRecord.fromJson(json)).toList();
    }

    try {
      return await run('*, employees!exception_records_employee_id_fkey(full_name, email, role, site_location), '
          'reviewer:employees!exception_records_reviewed_by_fkey(full_name)');
    } on PostgrestException {
      // Before migration 003 there is no reviewer relationship.
      return run('*, employees(full_name, email, role, site_location)');
    }
  }

  String buildCsv(List<ExceptionRecord> exceptions) {
    return _toCsv([
      ['Date', 'Employee', 'Email', 'Site', 'Type', 'Severity', 'Status', 'Description', 'Reviewed by', 'Reviewed at', 'Resolution note'],
      for (final ex in exceptions)
        [
          _dateFmt.format(ex.createdAt.toLocal()),
          ex.employeeName ?? ex.employeeId,
          ex.employeeEmail ?? '',
          ex.siteLocation ?? '',
          ex.typeTitle,
          ex.severity,
          ex.status,
          ex.description ?? '',
          ex.reviewedByName ?? '',
          (ex.reviewedAt ?? ex.resolvedAt) != null ? _dateFmt.format((ex.reviewedAt ?? ex.resolvedAt)!.toLocal()) : '',
          ex.resolutionNote ?? '',
        ],
    ]);
  }

  /// Roboto instead of the built-in Helvetica, which cannot draw characters
  /// such as "—" and "–" used in exception descriptions.
  static Future<pw.ThemeData>? _pdfTheme;
  static Future<pw.ThemeData> _loadPdfTheme() async => pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Roboto-Bold.ttf')),
      );

  Future<Uint8List> buildPdf(List<ExceptionRecord> exceptions, {required String organizationName, String? period}) async {
    final doc = pw.Document(
      title: 'Vigil compliance report',
      author: 'Vigil',
      theme: await (_pdfTheme ??= _loadPdfTheme()),
    );
    final counts = <String, int>{};
    for (final ex in exceptions) {
      counts[ex.severity] = (counts[ex.severity] ?? 0) + 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => _pdfHeader('Compliance report', organizationName),
        footer: _pdfFooter,
        build: (ctx) => [
          pw.SizedBox(height: 12),
          if (period != null) pw.Text('Period: $period', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 8),
          pw.Text(
            'Total exceptions: ${exceptions.length}   ·   '
            'Critical: ${counts['critical'] ?? 0}   High: ${counts['high'] ?? 0}   '
            'Medium: ${counts['medium'] ?? 0}   Low: ${counts['low'] ?? 0}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          if (exceptions.isEmpty)
            pw.Text('No exceptions were recorded for this period.')
          else
            pw.TableHelper.fromTextArray(
              headers: ['Date', 'Employee', 'Type', 'Severity', 'Status', 'Description'],
              data: [
                for (final ex in exceptions)
                  [
                    _dateFmt.format(ex.createdAt.toLocal()),
                    ex.employeeName ?? '—',
                    ex.typeTitle,
                    ex.severity,
                    ex.status,
                    ex.description ?? '',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellAlignments: {for (var i = 0; i < 6; i++) i: pw.Alignment.centerLeft},
              columnWidths: {
                0: const pw.FixedColumnWidth(90),
                1: const pw.FixedColumnWidth(110),
                2: const pw.FixedColumnWidth(140),
                3: const pw.FixedColumnWidth(55),
                4: const pw.FixedColumnWidth(70),
                5: const pw.FlexColumnWidth(),
              },
              oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            ),
        ],
      ),
    );
    return doc.save();
  }

  /// Saves (desktop/mobile) or downloads (web) the file. Returns the saved path.
  Future<String> saveCsv(String csv, String baseName) => FileSaver.instance.saveFile(
        name: baseName,
        bytes: Uint8List.fromList(utf8.encode('﻿$csv')),
        fileExtension: 'csv',
        mimeType: MimeType.csv,
      );

  Future<String> savePdf(Uint8List bytes, String baseName) => FileSaver.instance.saveFile(
        name: baseName,
        bytes: bytes,
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
}
