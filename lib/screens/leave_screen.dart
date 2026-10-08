import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/leave_provider.dart';
import '../providers/auth_provider.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Request marked as $status', style: const TextStyle(color: Colors.white)), 
          backgroundColor: status == 'approved' ? Colors.green : Colors.red,
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _deleteLeaveRequest(BuildContext context, WidgetRef ref, String id) async {
    try {
      await Supabase.instance.client.from('leave_requests').delete().eq('id', id);
      ref.refresh(leaveProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave request cancelled.'), backgroundColor: Colors.orange));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _showNewLeaveRequestDialog(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authProvider).currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    DateTime startDate = DateTime.now().add(const Duration(days: 1));
    DateTime endDate = DateTime.now().add(const Duration(days: 3));
    String selectedType = 'annual';
    final reasonController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateFormat = DateFormat('MMM d, yyyy');
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.beach_access, color: Color(0xFF38BDF8)),
                  const SizedBox(width: 12),
                  Text('New Leave Request', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('LEAVE TYPE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'annual', child: Text('Annual Leave')),
                          DropdownMenuItem(value: 'sick', child: Text('Sick Leave')),
                          DropdownMenuItem(value: 'unpaid', child: Text('Unpaid Leave')),
                          DropdownMenuItem(value: 'other', child: Text('Compassionate / Other')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedType = val);
                        },
                      ),
                      const SizedBox(height: 20),
                      const Text('DATE RANGE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.calendar_today, size: 16, color: Color(0xFF38BDF8)),
                              label: Text(dateFormat.format(startDate), style: const TextStyle(fontSize: 13)),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    startDate = picked;
                                    if (endDate.isBefore(startDate)) endDate = startDate;
                                  });
                                }
                              },
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text('to', style: TextStyle(color: Colors.white54)),
                          ),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.2)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              icon: const Icon(Icons.event, size: 16, color: Color(0xFF38BDF8)),
                              label: Text(dateFormat.format(endDate), style: const TextStyle(fontSize: 13)),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: endDate.isBefore(startDate) ? startDate : endDate,
                                  firstDate: startDate,
                                  lastDate: DateTime.now().add(const Duration(days: 365)),
                                );
                                if (picked != null) {
                                  setDialogState(() => endDate = picked);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text('REASON / NOTE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Enter reason or notes for your manager...',
                          hintStyle: const TextStyle(color: Colors.white30),
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withOpacity(0.1))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isSubmitting ? null : () async {
                    setDialogState(() => isSubmitting = true);
                    try {
                      await Supabase.instance.client.from('leave_requests').insert({
                        'organization_id': user.organizationId,
                        'employee_id': user.id,
                        'start_date': DateFormat('yyyy-MM-dd').format(startDate),
                        'end_date': DateFormat('yyyy-MM-dd').format(endDate),
                        'leave_type': selectedType,
                        'reason': reasonController.text.trim().isEmpty ? null : reasonController.text.trim(),
                        'status': 'pending',
                      });
                      ref.refresh(leaveProvider);
                      if (context.mounted) {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Leave request submitted successfully!'), 
                          backgroundColor: Colors.green,
                        ));
                      }
                    } catch (e) {
                      setDialogState(() => isSubmitting = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSubmitting 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Text('Submit Request', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaveAsync = ref.watch(leaveProvider);
    final theme = Theme.of(context);
    final currentUser = ref.watch(authProvider).currentUser;
    final isManager = currentUser?.role != 'staff';

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
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
            icon: const Icon(Icons.add),
            label: const Text('New Leave Request', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () => _showNewLeaveRequestDialog(context, ref),
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
              'Leave Approvals & Scheduling',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ).animate().fadeIn().slideY(begin: -0.2, end: 0),
            const SizedBox(height: 8),
            Text(
              'Manage employee time off and ensure Fair Work roster compliance.',
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
                      return _buildLeaveCard(context, ref, req, index, isManager, currentUser?.id);
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

  Widget _buildLeaveCard(BuildContext context, WidgetRef ref, LeaveRequest req, int index, bool isManager, String? currentUserId) {
    final isPending = req.status.toLowerCase() == 'pending';
    final isApproved = req.status.toLowerCase() == 'approved';
    final dateFormat = DateFormat('MMM d, yyyy');
    final isOwnRequest = currentUserId != null && currentUserId == req.employeeId;
    
    final dates = '${dateFormat.format(req.startDate)} - ${dateFormat.format(req.endDate)}';
    
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
                Row(
                  children: [
                    Text('Employee UID: ${req.employeeId.length > 8 ? req.employeeId.substring(0, 8) : req.employeeId}', 
                      style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                    if (isOwnRequest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                        child: const Text('YOU', style: TextStyle(fontSize: 10, color: Colors.blueAccent, fontWeight: FontWeight.bold)),
                      )
                    ]
                  ],
                ),
                Row(
                  children: [
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
                    ),
                    if (isPending && (isOwnRequest || isManager)) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white38),
                        tooltip: 'Cancel Request',
                        onPressed: () => _deleteLeaveRequest(context, ref, req.id),
                      )
                    ]
                  ],
                )
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.beach_access, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(req.leaveType.toUpperCase(), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
                const SizedBox(width: 24),
                const Icon(Icons.date_range, size: 16, color: Colors.white54),
                const SizedBox(width: 8),
                Text(dates, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            if (req.reason != null && req.reason!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Reason: ${req.reason}', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13, fontStyle: FontStyle.italic)),
            ],
            
            if (isPending && isManager) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent)),
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _updateStatus(context, ref, req.id, 'declined'), 
                    label: const Text('Decline'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green),
                    icon: const Icon(Icons.check, size: 16),
                    onPressed: () => _updateStatus(context, ref, req.id, 'approved'), 
                    label: const Text('Approve'),
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
