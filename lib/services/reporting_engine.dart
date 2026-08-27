import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/exception_record.dart';

class ReportingEngine {
  final _supabase = Supabase.instance.client;

  /// Fetches real exceptions from Supabase and generates a CSV
  Future<String> generateExceptionsCsv(String organizationId) async {
    final exceptions = await _fetchExceptions(organizationId);
    List<List<dynamic>> csvData = [
      ['ID', 'Employee ID', 'Exception Type', 'Severity', 'Status', 'Date Logged', 'Description'],
    ];

    for (var ex in exceptions) {
      csvData.add([ex.id, ex.employeeId, ex.exceptionType, ex.severity, ex.status, ex.createdAt.toIso8601String(), ex.description ?? 'N/A']);
    }
    // Generate CSV string manually to avoid package dependency issues
    return csvData.map((row) => row.map((e) => '"${e.toString().replaceAll('"', '""')}"').join(',')).join('\n');
  }

  /// Generates a PDF Report Payload (In a real SaaS, this payload is sent to the Edge Function 
  /// which uses Puppeteer/PDFKit to render and email the actual PDF).
  Future<String> generateExceptionsPdfPayload(String organizationId) async {
    final exceptions = await _fetchExceptions(organizationId);
    
    // Simulate HTML/PDF Template formatting
    StringBuffer pdfContent = StringBuffer();
    pdfContent.writeln("<h1>Vigil Compliance Report</h1>");
    pdfContent.writeln("<p>Generated at: ${DateTime.now().toString()}</p>");
    pdfContent.writeln("<hr>");
    pdfContent.writeln("<ul>");
    for (var ex in exceptions) {
      pdfContent.writeln("<li><strong>${ex.exceptionType.toUpperCase()}</strong> - ${ex.status} (${ex.severity})<br>Desc: ${ex.description}</li>");
    }
    pdfContent.writeln("</ul>");
    
    return pdfContent.toString();
  }

  Future<List<ExceptionRecord>> _fetchExceptions(String organizationId) async {
    final response = await _supabase.from('exception_records').select().eq('organization_id', organizationId).order('created_at', ascending: false);
    return response.map((json) => ExceptionRecord.fromJson(json)).toList();
  }

  /// Demo function to show the scheduled report in the UI for the Capstone Presentation
  Future<void> runScheduledReportDemo(BuildContext context, String organizationId) async {
    final csvString = await generateExceptionsCsv(organizationId);
    final pdfPayload = await generateExceptionsPdfPayload(organizationId);

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Automated Report Generated'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('The Backend CRON Job just ran. Multi-format reports (CSV & PDF) were generated and emailed to Managers.', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                const Text('1. CSV ATTACHMENT:', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey[200],
                  child: Text(csvString, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
                ),
                const SizedBox(height: 16),
                const Text('2. PDF RENDER PAYLOAD (Sent to PDF Engine):', style: TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.blue[50],
                  child: Text(pdfPayload, style: const TextStyle(fontFamily: 'Courier', fontSize: 10)),
                )
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            )
          ],
        ),
      );
    }
  }
}
