import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../providers/exception_provider.dart';
import '../models/exception_record.dart';
import '../providers/auth_provider.dart';
import '../widgets/premium_card.dart';
import '../widgets/animated_button.dart';
import '../widgets/agent_fab.dart';
import '../providers/theme_provider.dart';
import 'dart:ui';
import 'package:intl/intl.dart';
import '../widgets/staff_terminal_view.dart';
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
    final authState = ref.watch(authProvider);
    final user = authState.currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: _buildPremiumAppBar(context, user, ref),
      body: Row(
        children: [
          // Glassmorphic Sidebar
          _buildGlassSidebar(context, user).animate().fadeIn(duration: 400.ms).slideX(begin: -0.1, end: 0),
          // Main Content Area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: user?.role == 'staff' 
                  ? const StaffTerminalView() 
                  : (_activeTab == 0
                      ? _buildManagerView(context, ref, activeExceptionsAsync)
                      : const StaffTerminalView()),
            ),
          ),
        ],
      ),
      floatingActionButton: const AgentFAB(),
    );
  }

  PreferredSizeWidget _buildPremiumAppBar(BuildContext context, dynamic user, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Row(
        children: [
          Icon(Icons.security, color: theme.colorScheme.primary, size: 28)
            .animate(onPlay: (controller) => controller.repeat(reverse: true))
            .shimmer(duration: 2000.ms, color: Colors.white),
          const SizedBox(width: 12),
          Text(
            'Vigil',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              fontSize: 22,
            ),
          ),
          Container(
            margin: const EdgeInsets.only(left: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text(
              'Enterprise',
              style: TextStyle(fontSize: 10, color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ).animate().fadeIn(delay: 400.ms),
        ],
      ),
      actions: [
        if (user != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            margin: const EdgeInsets.only(right: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.domain, size: 16, color: Colors.white70),
                const SizedBox(width: 8),
                Text(
                  'ORG: ${user.organizationId.substring(0, 5).toUpperCase()}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ],
            ),
          ).animate().fadeIn(delay: 200.ms),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Text(
              '${user?.fullName ?? ''}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ).animate().fadeIn(delay: 300.ms),
        DropdownButtonHideUnderline(
          child: DropdownButton<AppTheme>(
            icon: Icon(Icons.palette, color: theme.colorScheme.primary),
            dropdownColor: theme.colorScheme.surface,
            value: ref.watch(themeProvider).currentTheme,
            items: AppTheme.values.map((AppTheme theme) {
              return DropdownMenuItem<AppTheme>(
                value: theme,
                child: Text(
                  theme.toString().split('.').last.toUpperCase(),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              );
            }).toList(),
            onChanged: (AppTheme? newTheme) {
              if (newTheme != null) {
                ref.read(themeProvider.notifier).setTheme(newTheme);
              }
            },
          ),
        ).animate().fadeIn(delay: 500.ms),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.logout, color: theme.colorScheme.error),
          tooltip: 'Logout',
          onPressed: () {
            ref.read(authProvider.notifier).logout();
            context.go('/');
          },
        ).animate().fadeIn(delay: 600.ms),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildGlassSidebar(BuildContext context, dynamic user) {
    final theme = Theme.of(context);
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          width: 260,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.4),
            border: Border(right: BorderSide(color: Colors.white.withValues(alpha: 0.05))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildNavItem(
                context, 
                Icons.dashboard, 
                'Live Dashboard', 
                user?.role == 'staff' || _activeTab == 0, 
                () {
                  if (mounted) setState(() => _activeTab = 0);
                },
              ),
              if (user?.role != 'staff')
                _buildNavItem(
                  context,
                  Icons.fingerprint,
                  'My Punch Terminal',
                  _activeTab == 1,
                  () {
                    if (mounted) setState(() => _activeTab = 1);
                  },
                ),
              _buildNavItem(context, Icons.people, 'Staff Directory', false, () => context.go('/staff')),
              _buildNavItem(context, Icons.calendar_month, 'Rosters & Scheduling', false, () => context.go('/rosters')),
              _buildNavItem(context, Icons.beach_access, 'Leave Management', false, () => context.go('/leave')),
              _buildNavItem(context, Icons.location_on, 'Geofence Zones', false, () => context.go('/geofence')),
              _buildNavItem(context, Icons.bar_chart, 'Compliance Reports', false, () => context.go('/reports')),
              if (user?.role == 'system_admin') ...[
                const SizedBox(height: 12),
                _buildNavItem(context, Icons.admin_panel_settings, 'System Admin', false, () => context.go('/admin'), colorOverride: Colors.orangeAccent),
              ],
              const Spacer(),
              const Divider(color: Colors.white12),
              _buildNavItem(context, Icons.settings, 'Settings', false, () => context.go('/settings')),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String title, bool isSelected, VoidCallback onTap, {Color? colorOverride}) {
    final theme = Theme.of(context);
    final color = colorOverride ?? (isSelected ? theme.colorScheme.primary : Colors.white60);
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Actionable Compliance Exceptions',
                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Roster breaches, unapproved overtime, geofence, and Fair Work alerts',
                    style: TextStyle(color: Colors.white60, fontSize: 14),
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
                        foregroundColor: const Color(0xFFA78BFA),
                        side: const BorderSide(color: Color(0xFF7C3AED)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: _isScanningCompliance
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)))
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
            Center(child: Text('Error loading exceptions: ${exceptionState.error}', style: const TextStyle(color: Colors.white)))
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Workforce Command Center',
                  style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(width: 14),
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
            const Text(
              'Real-time workforce attendance and compliance monitoring',
              style: TextStyle(color: Colors.white60),
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
              children: [
                Icon(
                  exceptions.isNotEmpty ? Icons.warning_amber_rounded : Icons.check_circle_outline,
                  color: exceptions.isNotEmpty ? Colors.orange : Colors.green,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${exceptions.length} Pending Exceptions',
                  style: TextStyle(
                    color: exceptions.isNotEmpty ? Colors.orange : Colors.green,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
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

    return Row(
      children: [
        Expanded(
          child: _buildKpiCard(
            title: 'On Shift Now',
            value: '${workforce.onShiftCount}',
            subtitle: 'Active staff clocked in',
            icon: Icons.badge_outlined,
            iconColor: const Color(0xFF10B981),
            glowColor: const Color(0xFF10B981),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            title: 'On Break',
            value: '${workforce.onBreakCount}',
            subtitle: 'Fair work rest/meal',
            icon: Icons.coffee,
            iconColor: Colors.amberAccent,
            glowColor: Colors.amberAccent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            title: 'Actionable Alerts',
            value: '$pendingCount',
            subtitle: 'Roster / geofence flags',
            icon: Icons.warning_amber,
            iconColor: pendingCount > 0 ? Colors.redAccent : Colors.white54,
            glowColor: pendingCount > 0 ? Colors.redAccent : Colors.transparent,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKpiCard(
            title: 'Total Roster',
            value: '${workforce.totalStaffCount}',
            subtitle: 'Registered organization staff',
            icon: Icons.people_outline,
            iconColor: const Color(0xFF3B82F6),
            glowColor: const Color(0xFF3B82F6),
          ),
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
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
              Text(title, style: const TextStyle(color: Colors.white60, fontSize: 13, fontWeight: FontWeight.w500)),
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
            style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Who's On Duty Right Now",
                        style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Live workforce attendance synced across all devices in real time',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: workforce.onShiftCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: workforce.onShiftCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.4) : Colors.white10),
                ),
                child: Text(
                  '${workforce.onShiftCount} Active On Shift',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: workforce.onShiftCount > 0 ? const Color(0xFF10B981) : Colors.white60,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white10),
          const SizedBox(height: 12),

          if (workforce.staffList.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text('No employees found in directory.', style: TextStyle(color: Colors.white54)),
              ),
            ),
          ] else ...[
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: workforce.staffList.length,
              separatorBuilder: (_, _) => const Divider(color: Colors.white10, height: 20),
              itemBuilder: (context, index) {
                final staff = workforce.staffList[index];
                final isClockedIn = staff.status == StaffWorkStatus.clockedIn;
                final isOnBreak = staff.status == StaffWorkStatus.onBreak;
                final worked = staff.currentDuration;
                final hours = worked.inHours;
                final mins = worked.inMinutes % 60;
                final durationStr = hours > 0 ? '${hours}h ${mins}m' : '${mins}m';

                return Row(
                  children: [
                    // Avatar with status ring
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          child: Text(
                            staff.fullName.isNotEmpty ? staff.fullName[0].toUpperCase() : '?',
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: Colors.white),
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
                                  : (isOnBreak ? Colors.amberAccent : Colors.white38),
                              border: Border.all(color: const Color(0xFF1E293B), width: 2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),

                    // Employee Name and Role/Location
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                staff.fullName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  staff.role.toUpperCase(),
                                  style: const TextStyle(fontSize: 10, color: Colors.white70, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${staff.email} • ${staff.siteLocation}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ],
                      ),
                    ),

                    // Live Status Badge & Ticking Time
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isClockedIn 
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15) 
                                      : (isOnBreak ? Colors.amberAccent.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isClockedIn 
                                        ? const Color(0xFF10B981).withValues(alpha: 0.4) 
                                        : (isOnBreak ? Colors.amberAccent.withValues(alpha: 0.4) : Colors.white10),
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
                                        : (isOnBreak ? Colors.amberAccent : Colors.white54),
                                  ),
                                ),
                              ),
                              if (isClockedIn) ...[
                                const SizedBox(width: 10),
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
                                ? 'Shift started at ${DateFormat('hh:mm a').format(staff.shiftStartTime!)}'
                                : 'No active shift today',
                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),

                    // Location / GPS Tag
                    Expanded(
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
                                color: staff.isGeofenced ? const Color(0xFF10B981) : Colors.amberAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                staff.isGeofenced ? 'Geofence Verified' : (staff.latitude != null ? 'GPS Tagged' : 'Terminal'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: staff.isGeofenced ? const Color(0xFF10B981) : Colors.white70,
                                ),
                              ),
                            ],
                          ),
                          if (staff.latitude != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${staff.latitude!.toStringAsFixed(2)}, ${staff.longitude!.toStringAsFixed(2)}',
                              style: GoogleFonts.firaCode(fontSize: 10, color: Colors.white38),
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
          Text('100% Compliant', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 8),
          const Text('No roster breaches or overtime exceptions detected.', style: TextStyle(color: Colors.white60)).animate().fadeIn(delay: 300.ms),
        ],
      ),
    );
  }

  Widget _buildExceptionFilterChip(String key, String label, {Color? color}) {
    final isSelected = _exceptionFilter == key;
    final activeColor = color ?? const Color(0xFF38BDF8);

    return InkWell(
      onTap: () => setState(() => _exceptionFilter = key),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? activeColor : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? activeColor : Colors.white70,
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
              Icon(inserted > 0 ? Icons.warning_amber_rounded : Icons.check_circle, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                inserted > 0
                    ? 'Compliance audit complete: $inserted new breach(es) detected and logged!'
                    : 'Compliance audit complete: 100% Fair Work compliant, no new breaches!',
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
          content: Text('Audit scan error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isScanningCompliance = false);
    }
  }

  Future<void> _showResolveDialog(BuildContext context, dynamic ex) async {
    final noteController = TextEditingController(text: ex.description ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.verified, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 12),
            Text('Resolve Exception', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
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
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text('Original Flag: ${ex.description}', style: const TextStyle(color: Colors.white60, fontSize: 13)),
              const SizedBox(height: 16),
              const Text('Resolution Notes / Manager Sign-off:', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'e.g. Overtime approved by site manager / Manual break verified...',
                  hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white60,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(exceptionServiceProvider).ignoreException(ex.id, reason: 'Dismissed: ${noteController.text}');
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Exception dismissed/ignored.'),
                  backgroundColor: Colors.blueGrey,
                  behavior: SnackBarBehavior.floating,
                ));
              }
            },
            child: const Text('Dismiss / Ignore'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            icon: const Icon(Icons.check, size: 16),
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: noteController.text);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Exception resolved and signed off.'),
                  backgroundColor: Color(0xFF10B981),
                  behavior: SnackBarBehavior.floating,
                ));
              }
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
        : (isHigh ? theme.colorScheme.error : (ex.severity == 'medium' ? Colors.orangeAccent : const Color(0xFF38BDF8)));

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
                      Row(
                        children: [
                          Text(
                            title,
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
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
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isResolved 
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15) 
                                  : (isAcknowledged ? Colors.amber.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: isResolved ? const Color(0xFF10B981) : (isAcknowledged ? Colors.amber : Colors.white60),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(ex.description ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.person, size: 16, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 6),
                          Text(
                            employeeDisplayName, 
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          if (ex is ExceptionRecord && ex.siteLocation != null) ...[
                            const SizedBox(width: 16),
                            const Icon(Icons.location_on_outlined, size: 14, color: Colors.white38),
                            const SizedBox(width: 4),
                            Text(ex.siteLocation!, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                          ],
                          const SizedBox(width: 20),
                          const Icon(Icons.access_time, size: 14, color: Colors.white38),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('MMM d, hh:mm a').format(ex.createdAt),
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (!isResolved) ...[
                      Row(
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
                              onPressed: () => _simulateAIResolve(ex.id),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.amber,
                                side: BorderSide(color: Colors.amber.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              onPressed: () => ref.read(exceptionServiceProvider).acknowledgeException(ex.id),
                              child: const Text('Acknowledge', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 8),
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
                     children: const [
                       SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF))),
                       SizedBox(width: 16),
                       Text('Synthesizing historical patterns & anomaly scoring...', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
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
                           const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 20),
                           const SizedBox(width: 12),
                           const Text('AI Anomaly Resolution Recommendation', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                         ],
                       ),
                       const SizedBox(height: 12),
                       Text(_aiSuggestion!, style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5)),
                       const SizedBox(height: 20),
                       Row(
                         children: [
                           SizedBox(
                             width: 180,
                             height: 44,
                             child: AnimatedButton(
                               text: 'Apply AI Sign-off',
                               onPressed: () {
                                 ref.read(exceptionServiceProvider).resolveException(ex.id, resolutionNote: _aiSuggestion);
                                 setState(() { _resolvingExceptionId = null; _aiSuggestion = null; });
                               },
                             ),
                           ),
                           const SizedBox(width: 16),
                           TextButton(
                             onPressed: () => setState(() { _resolvingExceptionId = null; _aiSuggestion = null; }),
                             child: const Text('Discard', style: TextStyle(color: Colors.white54)),
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

  void _simulateAIResolve(String exceptionId) {
    setState(() {
      _resolvingExceptionId = exceptionId;
      _aiSuggestion = null;
    });

    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _resolvingExceptionId == exceptionId) {
        setState(() {
          _aiSuggestion = "Vigil AI Engine: Pattern analysis shows regular shift schedule with zero unauthorized deviation history. Isolation Forest & XGBoost scored 0.02 anomaly risk. Recommendation: Approve automatically and clear flag.";
        });
      }
    });
  }
}

