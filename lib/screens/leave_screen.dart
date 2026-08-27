import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/leave_provider.dart';
import '../widgets/premium_card.dart';
import '../models/leave_request.dart';

class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, String id, String status) async {
    try {
      await Supabase.instance.client
          .from('leave_requests')
          .update({'status': status})
          .eq('id', id);
          
      ref.refresh(leaveProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Request marked as $status', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaveAsync = ref.watch(leaveProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Leave & Holiday Management', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: () => ref.refresh(leaveProvider),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
            icon: const Icon(Icons.add),
            label: const Text('New Leave Request'),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request form not implemented.')));
            },
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
              'Leave Approvals',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ).animate().fadeIn().slideY(begin: -0.2, end: 0),
            const SizedBox(height: 8),
            Text(
              'Manage employee time off and view potential roster conflicts.',
              style: TextStyle(color: Colors.white.withOpacity(0.6)),
            ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2, end: 0),
            const SizedBox(height: 32),
            Expanded(
              child: leaveAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err', style: const TextStyle(color: Colors.red))),
                data: (requests) {
                  if (requests.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle_outline, size: 64, color: Colors.white24).animate().scale(),
                          const SizedBox(height: 16),
                          Text('No pending leave requests.', style: GoogleFonts.outfit(fontSize: 20, color: Colors.white54)),
                        ],
                      )
                    );
                  }
                  
                  return ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final req = requests[index];
                      return _buildLeaveCard(context, ref, req, index);
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

  Widget _buildLeaveCard(BuildContext context, WidgetRef ref, LeaveRequest req, int index) {
    final isPending = req.status.toLowerCase() == 'pending';
    final isApproved = req.status.toLowerCase() == 'approved';
    final dateFormat = DateFormat('MMM d, yyyy');
    
    final dates = '${dateFormat.format(req.startDate)} - ${dateFormat.format(req.endDate)}';
    
    // Mock conflict detection based on ID for demo purposes
    final String? conflict = req.employeeId.startsWith('a') ? '⚠️ Conflict: Scheduled for a shift on ${dateFormat.format(req.startDate)}' : null;

    Color statusColor = isPending ? Colors.orange : (isApproved ? Colors.green : Colors.red);
    Color statusBg = statusColor.withOpacity(0.15);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: PremiumCard(
        blurRadius: 10,
        opacity: 0.05,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Employee ID: ${req.employeeId.substring(0,8)}', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Text(
                    req.status.toUpperCase(),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.beach_access, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(req.leaveType, style: const TextStyle(color: Colors.white70)),
                const SizedBox(width: 24),
                const Icon(Icons.date_range, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(dates, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Reason: ${req.reason ?? 'N/A'}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
            
            if (conflict != null && isPending) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Text(conflict, style: const TextStyle(color: Color(0xFFF87171), fontWeight: FontWeight.bold)),
              )
            ],
            
            if (isPending) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                    onPressed: () => _updateStatus(context, ref, req.id, 'declined'), 
                    child: const Text('Decline')
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () => _updateStatus(context, ref, req.id, 'approved'), 
                    child: const Text('Approve')
                  ),
                ],
              )
            ]
          ],
        ),
      ),
    ).animate().fadeIn(delay: (50 * index).ms).slideX(begin: 0.1, end: 0);
  }
}
