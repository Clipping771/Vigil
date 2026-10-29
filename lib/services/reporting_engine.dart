import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/exception_record.dart';

/// Builds compliance exports (CSV / PDF) from the organization's exceptions.
class ReportingEngine {
  SupabaseClient get _supabase => Supabase.instance.client;
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  Future<List<ExceptionRecord>> fetchExceptions(
    String organizationId, {
    DateTime? from,
    DateTime? to,
  }) async {
    var query = _supabase
        .from('exception_records')
        .select('*, employees(full_name, email, role, site_location)')
        .eq('organization_id', organizationId);
    if (from != null) query = query.gte('created_at', from.toUtc().toIso8601String());
    if (to != null) query = query.lt('created_at', to.toUtc().toIso8601String());
    final response = await query.order('created_at', ascending: false);
    return response.map((json) => ExceptionRecord.fromJson(json)).toList();
  }

  String buildCsv(List<ExceptionRecord> exceptions) {
    final rows = <List<Object?>>[
      ['Date', 'Employee', 'Email', 'Site', 'Type', 'Severity', 'Status', 'Description', 'Resolved at', 'Resolution note'],
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
          ex.resolvedAt != null ? _dateFmt.format(ex.resolvedAt!.toLocal()) : '',
          ex.resolutionNote ?? '',
        ],
    ];
    String cell(Object? v) {
      var s = (v ?? '').toString();
      // Neutralise spreadsheet formula injection.
      if (s.isNotEmpty && '=+-@'.contains(s[0])) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    return rows.map((r) => r.map(cell).join(',')).join('\r\n');
  }

  Future<Uint8List> buildPdf(List<ExceptionRecord> exceptions, {required String organizationName, String? period}) async {
    final doc = pw.Document(title: 'Vigil compliance report', author: 'Vigil');
    final counts = <String, int>{};
    for (final ex in exceptions) {
      counts[ex.severity] = (counts[ex.severity] ?? 0) + 1;
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (ctx) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('Vigil · Compliance report', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
            pw.Text(organizationName, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ],
        ),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Generated ${_dateFmt.format(DateTime.now())} · Page ${ctx.pageNumber}/${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
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
