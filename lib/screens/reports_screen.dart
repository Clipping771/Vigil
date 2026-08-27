import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/reporting_engine.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _scheduleFrequency = 'Weekly';

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Compliance Reports', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Automated Reporting Engine', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)).animate().fadeIn().slideY(begin: -0.2, end: 0),
            const SizedBox(height: 8),
            Text('Configure scheduled deliveries and export compliance data.', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 16)).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2, end: 0),
            const SizedBox(height: 40),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: _buildManualExportCard(context, user).animate().fadeIn(delay: 200.ms).slideX(begin: -0.1, end: 0),
                ),
                const SizedBox(width: 32),
                Expanded(
                  flex: 3,
                  child: _buildScheduledReportsCard(context, user).animate().fadeIn(delay: 300.ms).slideX(begin: 0.1, end: 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualExportCard(BuildContext context, dynamic user) {
    return PremiumCard(
      blurRadius: 10,
      opacity: 0.05,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF00E5FF).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3))), child: const Icon(Icons.file_download, color: Color(0xFF00E5FF))),
              const SizedBox(width: 16),
              Text('Manual Export', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Instantly export all historical and pending exceptions for audit purposes.', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6), padding: const EdgeInsets.all(16.0)),
              icon: const Icon(Icons.table_chart),
              label: const Text('Export to CSV'),
              onPressed: () async {
                if (user == null) return;
                final csvString = await ReportingEngine().generateExceptionsCsv(user.organizationId);
                _showReportPreview(context, 'CSV Data Generated', csvString);
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white38), padding: const EdgeInsets.all(16.0)),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Export to PDF'),
              onPressed: () async {
                if (user == null) return;
                final pdfPayload = await ReportingEngine().generateExceptionsPdfPayload(user.organizationId);
                _showReportPreview(context, 'PDF Render Payload Generated', pdfPayload);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledReportsCard(BuildContext context, dynamic user) {
    return PremiumCard(
      blurRadius: 10,
      opacity: 0.05,
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFF7C3AED).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3))), child: const Icon(Icons.schedule, color: Color(0xFFA78BFA))),
                  const SizedBox(width: 16),
                  Text('Scheduled Deliveries', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                ],
              ),
              Switch(value: true, onChanged: (v){}, activeColor: const Color(0xFF7C3AED)),
            ],
          ),
          const SizedBox(height: 24),
          Text('Automatically compile compliance issues and deliver them securely via email to regional managers and HR.', style: TextStyle(color: Colors.white.withOpacity(0.7))),
          const SizedBox(height: 32),
          Text('FREQUENCY', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), letterSpacing: 1.5)),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            style: SegmentedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              selectedForegroundColor: Colors.white,
              selectedBackgroundColor: const Color(0xFF3B82F6).withOpacity(0.3),
              side: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            segments: const [
              ButtonSegment(value: 'Daily', label: Text('Daily')),
              ButtonSegment(value: 'Weekly', label: Text('Weekly')),
              ButtonSegment(value: 'Monthly', label: Text('Monthly')),
            ],
            selected: {_scheduleFrequency},
            onSelectionChanged: (Set<String> newSelection) {
              setState(() => _scheduleFrequency = newSelection.first);
            },
          ),
          const SizedBox(height: 32),
          Text('DELIVERY METHOD', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.5), letterSpacing: 1.5)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Row(
              children: [
                const Icon(Icons.email, size: 20, color: Color(0xFF60A5FA)),
                const SizedBox(width: 12),
                const Text('Secure Email Link (Expires in 7 days)', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 48),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Test CRON Job Now'),
                onPressed: () {
                  if (user == null) return;
                  ReportingEngine().runScheduledReportDemo(context, user.organizationId);
                },
              ),
              const SizedBox(width: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Schedule updated successfully.')));
                },
                child: const Text('Save Configuration'),
              )
            ],
          )
        ],
      ),
    );
  }

  void _showReportPreview(BuildContext context, String title, String content) {
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        content: Container(
          width: 800,
          height: 400,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black45,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            child: Text(content, style: const TextStyle(fontFamily: 'Courier', fontSize: 12, color: Colors.white70)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}
