import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../providers/leave_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_provider.dart';
import '../providers/roster_provider.dart';
import '../widgets/premium_card.dart';
import '../models/leave_request.dart';
import '../models/shift.dart';

class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  String _selectedStatusTab = 'all'; // 'all', 'pending', 'approved', 'declined'
  final String _selectedTypeFilter = 'all'; // 'all', 'annual', 'sick', 'unpaid', 'compassionate', 'other'
  bool _onlyMyRequests = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      await ref.read(leaveStateProvider.notifier).updateStatus(id, status);
      if (mounted) {
        final isApproved = status == 'approved';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              Icon(isApproved ? Icons.check_circle : Icons.cancel, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text('Leave request successfully marked as ${status.toUpperCase()}'),
            ],
          ),
          backgroundColor: isApproved ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to update status: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _deleteLeaveRequest(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Cancel Leave Request?', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to withdraw this leave request? This action cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep', style: TextStyle(color: Colors.white54)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(leaveStateProvider.notifier).deleteLeaveRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Leave request cancelled and removed.'),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete request: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _showNewLeaveRequestDialog() async {
    final currentUser = ref.read(authProvider).currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please log in first.')));
      return;
    }

    final staffListAsync = ref.read(staffProvider);
    final staffList = staffListAsync.value ?? [];
    final isManager = currentUser.role != 'staff';

    String selectedEmployeeId = currentUser.id;
    String selectedType = 'annual';
    DateTimeRange dateRange = DateTimeRange(
      start: DateTime.now().add(const Duration(days: 1)),
      end: DateTime.now().add(const Duration(days: 3)),
    );
    final reasonController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final dateFormat = DateFormat('MMM d, yyyy');
            final totalDays = dateRange.end.difference(dateRange.start).inDays + 1;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.beach_access, color: Color(0xFF38BDF8), size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New Leave Request', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        Text('Submit for manager approval & roster review', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Employee Selector (if Manager/Admin)
                      if (isManager && staffList.isNotEmpty) ...[
                        const Text('APPLYING FOR EMPLOYEE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          initialValue: selectedEmployeeId,
                          dropdownColor: const Color(0xFF0F172A),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white.withValues(alpha: 0.05),
                            prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF38BDF8)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: currentUser.id,
                              child: Text('${currentUser.fullName} (Myself)', style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                            ...staffList.where((e) => e.id != currentUser.id).map((e) => DropdownMenuItem(
                              value: e.id,
                              child: Text('${e.fullName} (${e.role.toUpperCase()})'),
                            )),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedEmployeeId = val);
                          },
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Leave Type Selector
                      const Text('LEAVE TYPE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedType,
                        dropdownColor: const Color(0xFF0F172A),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          prefixIcon: Icon(_getLeaveTypeIcon(selectedType), color: _getLeaveTypeColor(selectedType)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'annual', child: Text('🌴 Annual Leave (Paid)')),
                          DropdownMenuItem(value: 'sick', child: Text('🩺 Sick / Carer\'s Leave (Paid)')),
                          DropdownMenuItem(value: 'unpaid', child: Text('⏳ Unpaid Leave')),
                          DropdownMenuItem(value: 'compassionate', child: Text('🤍 Compassionate Leave')),
                          DropdownMenuItem(value: 'maternity', child: Text('🍼 Maternity / Parental Leave')),
                          DropdownMenuItem(value: 'other', child: Text('📋 Other Special Leave')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedType = val);
                        },
                      ),
                      const SizedBox(height: 20),

                      // Date Range Picker
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('LEAVE DATES', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$totalDays ${totalDays == 1 ? 'Day' : 'Days'} Total',
                              style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () async {
                          final picked = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime.now().subtract(const Duration(days: 30)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                            initialDateRange: dateRange,
                            builder: (context, child) {
                              return Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: const ColorScheme.dark(
                                    primary: Color(0xFF38BDF8),
                                    onPrimary: Colors.black,
                                    surface: Color(0xFF1E293B),
                                    onSurface: Colors.white,
                                  ),
                                ),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            setDialogState(() => dateRange = picked);
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.date_range, color: Color(0xFF38BDF8), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '${dateFormat.format(dateRange.start)}   →   ${dateFormat.format(dateRange.end)}',
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                              ),
                              const Icon(Icons.edit_calendar, color: Colors.white38, size: 18),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Reason / Note
                      const Text('REASON / NOTES', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Add details, medical certificate notes, or travel plans...',
                          hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.05),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.all(20),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(
                    isSubmitting ? 'Submitting...' : 'Submit Request',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await ref.read(leaveStateProvider.notifier).createLeaveRequest(
                              employeeId: selectedEmployeeId,
                              leaveType: selectedType,
                              startDate: dateRange.start,
                              endDate: dateRange.end,
                              reason: reasonController.text,
                            );

                            if (context.mounted) {
                              Navigator.pop(dialogCtx);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: const Row(
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.white),
                                    SizedBox(width: 10),
                                    Text('Leave request submitted successfully!'),
                                  ],
                                ),
                                backgroundColor: const Color(0xFF10B981),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ));
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                              ));
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getLeaveTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'annual':
        return const Color(0xFF10B981); // Emerald
      case 'sick':
        return const Color(0xFFF59E0B); // Amber
      case 'unpaid':
        return const Color(0xFF8B5CF6); // Purple
      case 'compassionate':
        return const Color(0xFF0EA5E9); // Sky
      case 'maternity':
      case 'paternity':
        return const Color(0xFFEC4899); // Pink
      default:
        return const Color(0xFF94A3B8); // Slate
    }
  }

  IconData _getLeaveTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'annual':
        return Icons.beach_access;
      case 'sick':
        return Icons.local_hospital;
      case 'unpaid':
        return Icons.hourglass_empty;
      case 'compassionate':
        return Icons.volunteer_activism;
      case 'maternity':
      case 'paternity':
        return Icons.child_friendly;
      default:
        return Icons.event_note;
    }
  }

  @override
  Widget build(BuildContext context) {
    final leaveState = ref.watch(leaveStateProvider);
    final theme = Theme.of(context);
    final currentUser = ref.watch(authProvider).currentUser;
    final isManager = currentUser?.role != 'staff';
    final shiftsAsync = ref.watch(rosterProvider);
    final shifts = shiftsAsync.value ?? [];

    // Filter requests
    final allRequests = leaveState.requests;
    final filtered = allRequests.where((req) {
      // 1. Scope filter
      if (_onlyMyRequests || !isManager) {
        if (req.employeeId != currentUser?.id) return false;
      }

      // 2. Status tab filter
      if (_selectedStatusTab == 'pending' && !req.isPending) return false;
      if (_selectedStatusTab == 'approved' && !req.isApproved) return false;
      if (_selectedStatusTab == 'declined' && !req.isDeclined) return false;

      // 3. Type filter
      if (_selectedTypeFilter != 'all' && req.leaveType.toLowerCase() != _selectedTypeFilter) {
        return false;
      }

      // 4. Search query
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = (req.employeeName ?? '').toLowerCase();
        final email = (req.employeeEmail ?? '').toLowerCase();
        final reason = (req.reason ?? '').toLowerCase();
        final type = req.leaveType.toLowerCase();
        if (!name.contains(query) && !email.contains(query) && !reason.contains(query) && !type.contains(query)) {
          return false;
        }
      }

      return true;
    }).toList();

    // Leave balances for current user (Fair Work Australia benchmarks)
    final myApprovedRequests = allRequests.where((r) => r.employeeId == currentUser?.id && r.isApproved).toList();
    final myUsedAnnualDays = myApprovedRequests
        .where((r) => r.leaveType.toLowerCase() == 'annual')
        .fold<int>(0, (sum, r) => sum + r.durationDays);
    final myUsedSickDays = myApprovedRequests
        .where((r) => r.leaveType.toLowerCase() == 'sick')
        .fold<int>(0, (sum, r) => sum + r.durationDays);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.beach_access, color: Color(0xFF38BDF8), size: 20),
            ),
            const SizedBox(width: 12),
            Text('Leave & Holiday Management', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 20)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Data',
            onPressed: () => ref.read(leaveStateProvider.notifier).loadLeaveRequests(),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Leave Request', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _showNewLeaveRequestDialog,
          ),
          const SizedBox(width: 24),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Summary Row
            _buildKpiRow(allRequests, myUsedAnnualDays, myUsedSickDays, isManager),
            const SizedBox(height: 24),

            // Controls & Filters Row
            _buildFilterBar(allRequests, isManager),
            const SizedBox(height: 20),

            // Request Cards List
            Expanded(
              child: leaveState.isLoading && allRequests.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : leaveState.error != null && allRequests.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text('Failed to load leave requests', style: GoogleFonts.outfit(fontSize: 18, color: Colors.white)),
                              const SizedBox(height: 8),
                              Text(leaveState.error!, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: () => ref.read(leaveStateProvider.notifier).loadLeaveRequests(),
                                child: const Text('Try Again'),
                              ),
                            ],
                          ),
                        )
                      : filtered.isEmpty
                          ? _buildEmptyState()
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final req = filtered[index];
                                final isOwn = currentUser?.id == req.employeeId;

                                // Check shift conflicts
                                final conflicts = shifts.where((s) {
                                  if (s.employeeId != req.employeeId) return false;
                                  final sStart = DateTime(req.startDate.year, req.startDate.month, req.startDate.day);
                                  final sEnd = DateTime(req.endDate.year, req.endDate.month, req.endDate.day, 23, 59, 59);
                                  return s.startTime.isBefore(sEnd) && s.endTime.isAfter(sStart);
                                }).toList();

                                return _buildLeaveCard(req, index, isManager, isOwn, conflicts);
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow(List<LeaveRequest> allRequests, int usedAnnual, int usedSick, bool isManager) {
    final pendingCount = allRequests.where((r) => r.isPending).length;
    final onLeaveTodayCount = allRequests.where((r) => r.isOngoingToday).length;
    final approvedThisMonthCount = allRequests.where((r) => r.isApproved).length;

    final annualRemaining = (20 - usedAnnual).clamp(0, 20);
    final sickRemaining = (10 - usedSick).clamp(0, 10);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 48) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
              child: _buildMetricCard(
                title: 'PENDING APPROVALS',
                value: '$pendingCount',
                subtitle: pendingCount == 0 ? 'All requests reviewed' : 'Requires manager action',
                icon: Icons.hourglass_top_rounded,
                accentColor: const Color(0xFFF59E0B),
              ),
            ),
            SizedBox(
              width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
              child: _buildMetricCard(
                title: 'ON LEAVE TODAY',
                value: '$onLeaveTodayCount',
                subtitle: 'Active roster absentees',
                icon: Icons.beach_access,
                accentColor: const Color(0xFF38BDF8),
              ),
            ),
            SizedBox(
              width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
              child: _buildMetricCard(
                title: 'APPROVED LEAVES',
                value: '$approvedThisMonthCount',
                subtitle: 'Scheduled this cycle',
                icon: Icons.verified_rounded,
                accentColor: const Color(0xFF10B981),
              ),
            ),
            SizedBox(
              width: cardWidth < 220 ? constraints.maxWidth : cardWidth,
              child: _buildMetricCard(
                title: 'MY FAIR WORK BALANCE',
                value: '${annualRemaining}d Annual',
                subtitle: '${sickRemaining}d Sick leave remaining',
                icon: Icons.account_balance_wallet_outlined,
                accentColor: const Color(0xFFA855F7),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return PremiumCard(
      blurRadius: 10,
      opacity: 0.04,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: accentColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 4),
                Text(value, style: GoogleFonts.outfit(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(List<LeaveRequest> allRequests, bool isManager) {
    final pendingCount = allRequests.where((r) => r.isPending).length;
    final approvedCount = allRequests.where((r) => r.isApproved).length;
    final declinedCount = allRequests.where((r) => r.isDeclined).length;

    return Column(
      children: [
        Row(
          children: [
            // Tabs
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTabButton('all', 'All (${allRequests.length})'),
                    const SizedBox(width: 8),
                    _buildTabButton('pending', 'Pending ($pendingCount)', badgeColor: const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    _buildTabButton('approved', 'Approved ($approvedCount)', badgeColor: const Color(0xFF10B981)),
                    const SizedBox(width: 8),
                    _buildTabButton('declined', 'Declined ($declinedCount)', badgeColor: const Color(0xFFEF4444)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Search Box
            SizedBox(
              width: 260,
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search staff or notes...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.04),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
              ),
            ),

            if (isManager) ...[
              const SizedBox(width: 12),
              // Filter My Leaves Only Toggle
              FilterChip(
                label: const Text('My Requests Only', style: TextStyle(fontSize: 12)),
                selected: _onlyMyRequests,
                onSelected: (val) => setState(() => _onlyMyRequests = val),
                backgroundColor: Colors.white.withValues(alpha: 0.04),
                selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                checkmarkColor: const Color(0xFF38BDF8),
                side: BorderSide(color: _onlyMyRequests ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.1)),
                labelStyle: TextStyle(color: _onlyMyRequests ? const Color(0xFF38BDF8) : Colors.white70),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildTabButton(String tabKey, String label, {Color? badgeColor}) {
    final isSelected = _selectedStatusTab == tabKey;
    return InkWell(
      onTap: () => setState(() => _selectedStatusTab = tabKey),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF38BDF8).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF38BDF8) : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveCard(LeaveRequest req, int index, bool isManager, bool isOwnRequest, List<Shift> conflicts) {
    final dateFormat = DateFormat('MMM d, yyyy');
    final dates = '${dateFormat.format(req.startDate)}  –  ${dateFormat.format(req.endDate)}';
    final totalDays = req.durationDays;

    final typeColor = _getLeaveTypeColor(req.leaveType);
    final typeIcon = _getLeaveTypeIcon(req.leaveType);

    Color statusColor;
    String statusLabel = req.status.toUpperCase();
    if (req.isApproved) {
      statusColor = const Color(0xFF10B981);
    } else if (req.isDeclined) {
      statusColor = const Color(0xFFEF4444);
    } else {
      statusColor = const Color(0xFFF59E0B);
    }

    final displayName = req.employeeName ?? (req.employeeEmail != null ? req.employeeEmail!.split('@').first : 'Employee #${req.employeeId.substring(0, 6)}');
    final initials = displayName.isNotEmpty ? displayName.substring(0, 1).toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: PremiumCard(
        blurRadius: 12,
        opacity: 0.05,
        padding: const EdgeInsets.all(22.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Row: Employee Profile + Status Badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: typeColor.withValues(alpha: 0.2),
                      child: Text(
                        initials,
                        style: GoogleFonts.outfit(color: typeColor, fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(displayName, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                            if (isOwnRequest) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.4)),
                                ),
                                child: const Text('YOU', style: TextStyle(fontSize: 10, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                              ),
                            ],
                            if (req.employeeRole != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(req.employeeRole!.toUpperCase(), style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (req.employeeEmail != null) ...[
                              Text(req.employeeEmail!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                              const SizedBox(width: 12),
                            ],
                            if (req.employeeSite != null) ...[
                              const Icon(Icons.location_on_outlined, size: 13, color: Colors.white38),
                              const SizedBox(width: 3),
                              Text(req.employeeSite!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ],
                ),

                // Status Badge & Cancel Action
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            req.isApproved ? Icons.check_circle : (req.isDeclined ? Icons.cancel : Icons.hourglass_top),
                            size: 13,
                            color: statusColor,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            statusLabel,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.8),
                          ),
                        ],
                      ),
                    ),
                    if (req.isPending && (isOwnRequest || isManager)) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.white38),
                        tooltip: 'Withdraw Request',
                        onPressed: () => _deleteLeaveRequest(req.id),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 16),

            // Middle Row: Leave Type, Date Range, Duration
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: typeColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(typeIcon, size: 14, color: typeColor),
                      const SizedBox(width: 6),
                      Text(
                        req.leaveType.toUpperCase(),
                        style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                const Icon(Icons.date_range, size: 15, color: Colors.white54),
                const SizedBox(width: 6),
                Text(dates, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$totalDays ${totalDays == 1 ? 'Day' : 'Days'}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                if (req.isOngoingToday) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('ON LEAVE TODAY', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),

            // Conflict Warning Banner (if shift overlaps)
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Roster Conflict: ${conflicts.length} scheduled shift(s) overlap with this leave period. Approving will require reassignment.',
                        style: const TextStyle(color: Color(0xFFFCD34D), fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Reason Section
            if (req.reason != null && req.reason!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.format_quote, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        req.reason!,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13, fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Manager Action Buttons
            if (req.isPending && isManager) ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => _updateStatus(req.id, 'declined'),
                    label: const Text('Decline Request'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    onPressed: () => _updateStatus(req.id, 'approved'),
                    label: const Text('Approve Leave', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(delay: (40 * index).ms).slideY(begin: 0.05, end: 0);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.beach_access, size: 48, color: Colors.white24),
          ),
          const SizedBox(height: 16),
          Text('No Leave Requests Found', style: GoogleFonts.outfit(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'No requests matched your filter or search criteria.'
                : 'There are currently no leave applications in this view.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Submit New Request', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: _showNewLeaveRequestDialog,
          ),
        ],
      ),
    );
  }
}
