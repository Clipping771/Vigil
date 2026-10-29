import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/agent_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/exception_provider.dart';
import '../models/exception_record.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';
import '../widgets/app_shell.dart';
import 'package:intl/intl.dart';
import '../widgets/staff_terminal_view.dart';
import '../theme/ui.dart';
import '../providers/live_workforce_provider.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _resolvingExceptionId;
  String? _aiSuggestion;
  int _activeTab = 0; // 0: Manager Overview, 1: My Clock Terminal
  String _exceptionFilter = 'active'; // 'active', 'critical', 'all', 'resolved'
  bool _isScanningCompliance = false;

  @override
  Widget build(BuildContext context) {
    final activeExceptionsAsync = ref.watch(activeExceptionsProvider);
    final user = ref.watch(authProvider).currentUser;
    final isManager = user?.isManager ?? false;
    final showTerminal = !isManager || _activeTab == 1;
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(
        leading: ShellMenuButton.maybe(context),
        title: Text(isManager ? 'Dashboard' : 'My Shift'),
        actions: [
          if (isManager)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.insights_outlined, size: 18), label: compact ? null : const Text('Overview')),
                  ButtonSegment(value: 1, icon: const Icon(Icons.fingerprint, size: 18), label: compact ? null : const Text('My Punch Clock')),
                ],
                selected: {_activeTab},
                onSelectionChanged: (v) => setState(() => _activeTab = v.first),
              ),
            ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: showTerminal ? const StaffTerminalView() : _buildManagerView(context, ref, activeExceptionsAsync),
      ),
    );
  }

  Widget _buildManagerView(BuildContext context, WidgetRef ref, AsyncValue activeExceptionsAsync) {
    final workforce = ref.watch(workforceProvider);
    final exceptionState = ref.watch(exceptionStateProvider);
    final filteredExceptions = exceptionState.allExceptions.where((e) {
      if (_exceptionFilter == 'active') return !e.isResolved && !e.isIgnored;
      if (_exceptionFilter == 'critical') return e.isCritical || e.isHigh;
      if (_exceptionFilter == 'resolved') return e.isResolved;
      return true;
    }).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDashboardHeader(activeExceptionsAsync, workforce).animate().fadeIn().slideY(begin: -0.2, end: 0),
          const SizedBox(height: 24),

          // 1. REAL-TIME WORKFORCE METRIC CARDS
          _buildWorkforceKpiRow(workforce, activeExceptionsAsync),
          const SizedBox(height: 32),

          // 2. LIVE WHO'S ON DUTY FEED (Real-Time Attendance)
          _buildLiveAttendanceFeed(context, workforce),
          const SizedBox(height: 36),

          // 3. ACTIONABLE EXCEPTIONS SECTION
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actionable Compliance Exceptions',
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: context.fg()),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Roster breaches, unapproved overtime, geofence, and Fair Work alerts',
                    style: TextStyle(color: context.fg(0.6), fontSize: 14),
                  ),
                ],
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildExceptionFilterChip('active', 'Active (${exceptionState.activeCount})'),
                    const SizedBox(width: 8),
                    _buildExceptionFilterChip('critical', 'Critical (${exceptionState.criticalCount})', color: Colors.redAccent),
                    const SizedBox(width: 8),
                    _buildExceptionFilterChip('all', 'All (${exceptionState.allExceptions.length})'),
                    const SizedBox(width: 8),
                    _buildExceptionFilterChip('resolved', 'Resolved (${exceptionState.resolvedCount})', color: const Color(0xFF10B981)),
                    const SizedBox(width: 14),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF7C3AED).withValues(alpha: 0.2),
                        foregroundColor: const Color(0xFF8B5CF6),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: _isScanningCompliance
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)))
                          : const Icon(Icons.policy_outlined, size: 16),
                      label: Text(_isScanningCompliance ? 'Auditing...' : 'Run Audit Scan', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _isScanningCompliance ? null : _triggerComplianceScan,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (exceptionState.isLoading && exceptionState.allExceptions.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(32.0), child: CircularProgressIndicator()))
          else if (exceptionState.error != null && exceptionState.allExceptions.isEmpty)
            Center(child: Text('Error loading exceptions: ${exceptionState.error}', style: TextStyle(color: context.fg())))
          else if (filteredExceptions.isEmpty)
            _buildEmptyState()
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredExceptions.length,
              itemBuilder: (context, index) {
                return _buildExceptionRow(context, ref, filteredExceptions[index], workforce)
                    .animate()
                    .fadeIn(delay: (40 * index).ms)
                    .slideX(begin: 0.05, end: 0);
              },
            ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDashboardHeader(AsyncValue activeExceptionsAsync, WorkforceState workforce) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 14,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Workforce overview',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'LIVE REALTIME',
                        style: TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Real-time workforce attendance and compliance monitoring',
              style: TextStyle(color: context.fg(0.6)),
            )
          ],
        ),
        activeExceptionsAsync.when(
          data: (exceptions) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: exceptions.isNotEmpty ? Colors.orange.withValues(alpha: 0.15) : Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: exceptions.isNotEmpty ? Colors.orange.withValues(alpha: 0.5) : Colors.green.withValues(alpha: 0.5)),
              boxShadow: [
                 if (exceptions.isNotEmpty)
                    BoxShadow(color: Colors.orange.withValues(alpha: 0.2), blurRadius: 20, spreadRadius: -5)
              ]
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  exceptions.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: exceptions.isNotEmpty ? Colors.orange : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                  '${exceptions.length} pending exceptions',
                  style: TextStyle(
                    color: exceptions.isNotEmpty ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ),
              ],
            ),
          ).animate(onPlay: (controller) => exceptions.isNotEmpty ? controller.repeat(reverse: true) : null)
           .scale(begin: const Offset(1, 1), end: const Offset(1.05, 1.05), duration: 1.seconds),
          loading: () => const SizedBox(),
          error: (_, _) => const SizedBox(),
        ),
      ],
    );
  }

  Widget _buildWorkforceKpiRow(WorkforceState workforce, AsyncValue activeExceptionsAsync) {
    final pendingCount = activeExceptionsAsync.value?.length ?? 0;

    return _ResponsiveRow(
      children: [
        _buildKpiCard(
            title: 'On Shift Now',
            value: '${workforce.onShiftCount}',
            subtitle: 'Active staff clocked in',
            icon: Icons.badge_outlined,
            iconColor: const Color(0xFF10B981),
            glowColor: const Color(0xFF10B981),
        ),
        _buildKpiCard(
            title: 'On Break',
            value: '${workforce.onBreakCount}',
            subtitle: 'Fair work rest/meal',
            icon: Icons.coffee,
            iconColor: const Color(0xFFF59E0B),
            glowColor: const Color(0xFFF59E0B),
        ),
        _buildKpiCard(
            title: 'Actionable Alerts',
            value: '$pendingCount',
            subtitle: 'Roster / geofence flags',
            icon: Icons.warning_amber,
            iconColor: pendingCount > 0 ? Colors.redAccent : context.fg(0.54),
            glowColor: pendingCount > 0 ? Colors.redAccent : Colors.transparent,
        ),
        _buildKpiCard(
            title: 'Total Roster',
            value: '${workforce.totalStaffCount}',
            subtitle: 'Registered organization staff',
            icon: Icons.people_outline,
            iconColor: const Color(0xFF3B82F6),
            glowColor: const Color(0xFF3B82F6),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required Color glowColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.fg().withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.fg().withValues(alpha: 0.08)),
        boxShadow: [
          if (glowColor != Colors.transparent)
            BoxShadow(color: glowColor.withValues(alpha: 0.08), blurRadius: 20, spreadRadius: -5),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.fg(0.6), fontSize: 13, fontWeight: FontWeight.w500))),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: context.fg()),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: context.fg(0.38), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildLiveAttendanceFeed(BuildContext context, WorkforceState workforce) {
    return PremiumCard(
      blurRadius: 20,
      opacity: 0.08,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.people_alt, color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 14),
                  Flexible(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Who's On Duty Right Now",
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: context.fg()),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Live attendance, updated in real time',
                        style: TextStyle(color: context.fg(0.54), fontSize: 13),
                      ),
                    ],
                  ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: workforce.onShiftCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.15) : context.fg().withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: workforce.onShiftCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.4) : context.fg(0.1)),
                ),
                child: Text(
                  '${workforce.onShiftCount} Active On Shift',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: workforce.onShiftCount > 0 ? const Color(0xFF10B981) : context.fg(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Divider(color: context.fg(0.1)),
          const SizedBox(height: 12),

          if (workforce.staffList.isEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No employees found in directory.', style: TextStyle(color: context.fg(0.54))),
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: workforce.staffList.length,
              separatorBuilder: (_, _) => Divider(color: context.fg(0.1), height: 20),
              itemBuilder: (context, index) {
                final staff = workforce.staffList[index];
                final isClockedIn = staff.status == StaffWorkStatus.clockedIn;
                final isOnBreak = staff.status == StaffWorkStatus.onBreak;
                final worked = staff.currentDuration;
                final hours = worked.inHours;
                final mins = worked.inMinutes % 60;
                final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';
                final compact = MediaQuery.sizeOf(context).width < 700;

                return Row(
                  children: [
                    // Avatar with status ring
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: context.fg().withValues(alpha: 0.1),
                          child: Text(
                            staff.fullName.isNotEmpty ? staff.fullName[0].toUpperCase() : '?',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: context.fg()),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isClockedIn 
                                  ? const Color(0xFF10B981) 
                                  : (isOnBreak ? const Color(0xFFF59E0B) : context.fg(0.38)),
                              border: Border.all(color: context.surfaceHigh, width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(width: compact ? 12 : 16),

                    // Employee Name and Role/Location
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                staff.fullName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: context.fg()),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: context.fg().withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  staff.role.toUpperCase(),
                                  style: TextStyle(fontSize: 10, color: context.fg(0.7), fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${staff.email} • ${staff.siteLocation}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.fg(0.54), fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    // Live Status Badge & Ticking Time
                    if (!compact) const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isClockedIn 
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15) 
                                      : (isOnBreak ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : context.fg().withValues(alpha: 0.05)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isClockedIn 
                                        ? const Color(0xFF10B981).withValues(alpha: 0.4) 
                                        : (isOnBreak ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : context.fg(0.1)),
                                  ),
                                ),
                                child: Text(
                                  isClockedIn 
                                      ? 'CLOCKED IN' 
                                      : (isOnBreak ? 'ON BREAK' : 'OFF DUTY'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: isClockedIn 
                                        ? const Color(0xFF10B981) 
                                        : (isOnBreak ? const Color(0xFFF59E0B) : context.fg(0.54)),
                                  ),
                                ),
                              ),
                              if (isClockedIn) ...[
                                Text(
                                  '$durationStr on duty',
                                  style: GoogleFonts.firaCode(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            staff.shiftStartTime != null
                                ? 'Started ${DateFormat('h:mm a').format(staff.shiftStartTime!.toLocal())}'
                                : 'No active shift today',
                            style: TextStyle(fontSize: 11, color: context.fg(0.38)),
                          ),
                        ],
                      ),
                    ),

                    // Location / GPS Tag (hidden on narrow screens)
                    if (!compact) Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                staff.isGeofenced ? Icons.verified_outlined : Icons.location_on_outlined,
                                size: 14,
                                color: staff.isGeofenced ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                staff.isGeofenced ? 'Geofence Verified' : (staff.latitude != null ? 'GPS Tagged' : 'Terminal'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: staff.isGeofenced ? const Color(0xFF10B981) : context.fg(0.7),
                                ),
                              ),
                            ],
                          ),
                          if (staff.latitude != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${staff.latitude!.toStringAsFixed(2)}, ${staff.longitude!.toStringAsFixed(2)}',
                              style: GoogleFonts.firaCode(fontSize: 10, color: context.fg(0.38)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.green.withValues(alpha: 0.2), blurRadius: 40)],
            ),
            child: const Icon(Icons.shield_outlined, size: 80, color: Colors.green),
          ).animate().scale(curve: Curves.easeOutBack, duration: 600.ms),
          const SizedBox(height: 32),
          Text('100% Compliant', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: context.fg())).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          Text('No roster breaches or overtime exceptions detected.', style: TextStyle(color: context.fg(0.6))).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  Widget _buildExceptionFilterChip(String key, String label, {Color? color}) {
    final isSelected = _exceptionFilter == key;
    final activeColor = color ?? const Color(0xFF0EA5E9);

    return InkWell(
      onTap: () => setState(() => _exceptionFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : context.fg().withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : context.fg().withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? activeColor : context.fg(0.7),
          ),
        ),
      ),
    );
  }

  Future<void> _triggerComplianceScan() async {
    setState(() => _isScanningCompliance = true);
    try {
      final inserted = await ref.read(exceptionServiceProvider).runComplianceScan();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(
            children: [
              Icon(inserted > 0 ? Icons.warning_amber_rounded : Icons.check_circle, color: context.fg()),
              const SizedBox(width: 10),
              Text(
                inserted > 0
                    ? 'Scan complete: $inserted new issue(s) found.'
                    : 'Scan complete: no new issues found.',
              ),
            ],
          ),
          backgroundColor: inserted > 0 ? Colors.orange.shade800 : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('The compliance scan failed. Check your connection and try again.'),
        ));
      }
    } finally {
      if (mounted) setState(() => _isScanningCompliance = false);
    }
  }

  Future<void> _showResolveDialog(BuildContext context, dynamic ex) async {
    final noteController = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: context.fg().withValues(alpha: 0.1))),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 12),
            Text('Resolve Exception', style: GoogleFonts.outfit(color: context.fg(), fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ex is ExceptionRecord ? ex.typeTitle : ex.exceptionType.replaceAll('_', ' ').toUpperCase(),
                style: TextStyle(color: context.fg(), fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text('Original Flag: ${ex.description}', style: TextStyle(color: context.fg(0.6), fontSize: 13)),
              const SizedBox(height: 16),
              Text('Resolution Notes / Manager Sign-off:', style: TextStyle(color: context.fg(0.54), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 3,
                style: TextStyle(color: context.fg()),
                decoration: InputDecoration(
                  hintText: 'e.g. Overtime approved by site manager / Manual break verified...',
                  hintStyle: TextStyle(color: context.fg(0.3), fontSize: 12),
                  filled: true,
                  fillColor: context.fg().withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.fg().withValues(alpha: 0.1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.fg().withValues(alpha: 0.1))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: context.fg(0.54))),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: context.fg(0.6),
              side: BorderSide(color: context.fg().withValues(alpha: 0.2)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _runExceptionAction(
                () => ref.read(exceptionServiceProvider).ignoreException(ex.id, reason: noteController.text.trim().isEmpty ? null : noteController.text.trim()),
                'Exception dismissed.',
              );
            },
            child: const Text('Dismiss / Ignore'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            icon: const Icon(Icons.check, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await _runExceptionAction(
                () => ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: noteController.text.trim().isEmpty ? null : noteController.text.trim()),
                'Exception resolved.',
              );
            },
            label: const Text('Mark Resolved', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildExceptionRow(BuildContext context, WidgetRef ref, dynamic ex, WorkforceState workforce) {
    final theme = Theme.of(context);
    final isCritical = ex.severity == 'critical';
    final isHigh = ex.severity == 'high';
    final severityColor = isCritical 
        ? const Color(0xFFDC2626) 
        : (isHigh ? theme.colorScheme.error : (ex.severity == 'medium' ? Colors.orange.shade700 : const Color(0xFF0EA5E9)));

    final isResolving = _resolvingExceptionId == ex.id;
    final hasSuggestion = _aiSuggestion != null && _resolvingExceptionId == ex.id;

    final employeeDisplayName = (ex is ExceptionRecord && ex.employeeName != null)
        ? ex.employeeName!
        : (workforce.employeeNames[ex.employeeId] ?? ex.employeeId.substring(0, 8));

    final title = ex is ExceptionRecord ? ex.typeTitle : ex.exceptionType.replaceAll('_', ' ').toUpperCase();
    final status = ex.status?.toString().toLowerCase() ?? 'pending';
    final isResolved = status == 'resolved';
    final isAcknowledged = status == 'acknowledged';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: PremiumCard(
        blurRadius: 20,
        opacity: 0.05,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 64,
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: severityColor.withValues(alpha: 0.5), blurRadius: 10)],
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: context.fg()),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: severityColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: severityColor.withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              ex.severity.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: severityColor, letterSpacing: 1),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isResolved 
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15) 
                                  : (isAcknowledged ? Colors.amber.withValues(alpha: 0.15) : context.fg().withValues(alpha: 0.06)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isResolved ? const Color(0xFF10B981) : (isAcknowledged ? Colors.amber : context.fg(0.6)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(ex.description ?? '', style: TextStyle(color: context.fg(0.7), fontSize: 14)),
                      const SizedBox(height: 12),
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: [
                          const Icon(Icons.person, size: 16, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 6),
                          Text(
                            employeeDisplayName, 
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: context.fg()),
                          ),
                          if (ex is ExceptionRecord && ex.siteLocation != null) ...[
                            const SizedBox(width: 16),
                            Icon(Icons.location_on_outlined, size: 14, color: context.fg(0.38)),
                            const SizedBox(width: 4),
                            Text(ex.siteLocation!, style: TextStyle(fontSize: 12, color: context.fg(0.54))),
                          ],
                          const SizedBox(width: 20),
                          Icon(Icons.access_time, size: 14, color: context.fg(0.38)),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('MMM d, hh:mm a').format(ex.createdAt),
                            style: TextStyle(fontSize: 12, color: context.fg(0.54)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    if (!isResolved) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (status == 'pending') ...[
                            OutlinedButton.icon(
                              icon: const Icon(Icons.auto_awesome, size: 15, color: Color(0xFF7C3AED)),
                              label: const Text('AI Suggestion', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold, fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: const Color(0xFF7C3AED).withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _requestAiSuggestion(ex as ExceptionRecord),
                            ),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD97706),
                                side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => _runExceptionAction(
                                () => ref.read(exceptionServiceProvider).acknowledgeException(ex.id),
                                'Exception acknowledged.',
                              ),
                              child: const Text('Acknowledge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            icon: const Icon(Icons.check, size: 16),
                            onPressed: () => _showResolveDialog(context, ex),
                            label: const Text('Resolve', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          ),
                        ],
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, color: Color(0xFF10B981), size: 14),
                            SizedBox(width: 6),
                            Text('Resolved & Closed', style: TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                    ],
                  ),
                ),
              ],
            ),
            
            // AI Interaction simulation panel
            if (isResolving && !hasSuggestion)
               Padding(
                 padding: const EdgeInsets.only(top: 24.0, left: 26.0),
                 child: Container(
                   padding: const EdgeInsets.all(20),
                   decoration: BoxDecoration(
                     color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.3)),
                   ),
                   child: Row(
                     children: [
                       SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF06B6D4))),
                       SizedBox(width: 16),
                       Expanded(child: Text('Asking Vigil AI for a recommendation…', style: TextStyle(color: context.fg(0.7), fontStyle: FontStyle.italic))),
                     ],
                   ),
                 ),
               ).animate().fadeIn().slideY(begin: -0.1, end: 0),
            
            if (hasSuggestion)
               Padding(
                 padding: const EdgeInsets.only(top: 24.0, left: 26.0),
                 child: Container(
                   padding: const EdgeInsets.all(20),
                   decoration: BoxDecoration(
                     color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.5)),
                     boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withValues(alpha: 0.1), blurRadius: 20)],
                   ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Row(
                         children: [
                           const Icon(Icons.auto_awesome, color: Color(0xFF06B6D4), size: 20),
                           const SizedBox(width: 12),
                           Expanded(child: Text('AI recommendation', style: TextStyle(fontWeight: FontWeight.bold, color: context.fg(), fontSize: 16))),
                         ],
                       ),
                       const SizedBox(height: 12),
                       Text(_aiSuggestion!, style: TextStyle(fontSize: 14, color: context.fg(0.7), height: 1.5)),
                       const SizedBox(height: 8),
                       Text('AI-generated — verify before acting.', style: Theme.of(context).textTheme.bodySmall),
                       const SizedBox(height: 16),
                       Wrap(
                         spacing: 12,
                         runSpacing: 8,
                         children: [
                           FilledButton.icon(
                             icon: const Icon(Icons.check, size: 16),
                             label: const Text('Resolve with this note'),
                             onPressed: () {
                               final note = 'AI-assisted: ${_aiSuggestion!}';
                               setState(() { _resolvingExceptionId = null; _aiSuggestion = null; });
                               _runExceptionAction(
                                 () => ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: note),
                                 'Exception resolved.',
                               );
                             },
                           ),
                           TextButton(
                             onPressed: () => setState(() { _resolvingExceptionId = null; _aiSuggestion = null; }),
                             child: Text('Discard', style: TextStyle(color: context.fg(0.54))),
                           )
                         ],
                       )
                     ],
                   ),
                 ),
               ).animate().fadeIn().scale(curve: Curves.easeOutBack, duration: 400.ms)
          ],
        ),
      ),
    );
  }

  Future<void> _requestAiSuggestion(ExceptionRecord ex) async {
    setState(() {
      _resolvingExceptionId = ex.id;
      _aiSuggestion = null;
    });
    try {
      final text = await ref.read(agentServiceProvider).suggestResolution(
            type: ex.typeTitle,
            severity: ex.severity,
            description: ex.description ?? '',
            employeeName: ex.employeeName,
          );
      if (mounted && _resolvingExceptionId == ex.id) setState(() => _aiSuggestion = text);
    } catch (e) {
      if (!mounted) return;
      setState(() => _resolvingExceptionId = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e is AgentUnavailable ? e.message : 'Vigil AI is unavailable right now.'),
        action: SnackBarAction(label: 'Settings', onPressed: () => context.go('/settings')),
      ));
    }
  }

  Future<void> _runExceptionAction(Future<void> Function() action, String success) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(success)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not update the exception. You may not have permission.')));
    }
  }
}



/// Lays children out in equal-width columns that wrap on narrow screens.
class _ResponsiveRow extends StatelessWidget {
  final List<Widget> children;
  const _ResponsiveRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      final columns = c.maxWidth >= 1000 ? children.length : (c.maxWidth >= 520 ? 2 : 1);
      final width = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final child in children) SizedBox(width: width, child: child)],
      );
    });
  }
}
