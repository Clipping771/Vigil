import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/exception_provider.dart';
import '../providers/auth_provider.dart';
import '../services/clock_service.dart';
import '../widgets/premium_card.dart';
import '../widgets/animated_button.dart';
import '../widgets/agent_fab.dart';
import '../providers/theme_provider.dart';
import 'dart:ui';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  String? _resolvingExceptionId;
  String? _aiSuggestion;

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
                  ? _buildStaffView(context, ref) 
                  : _buildManagerView(context, ref, activeExceptionsAsync),
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
              color: theme.colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
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
              color: theme.colorScheme.surface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
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
            color: theme.colorScheme.surface.withOpacity(0.4),
            border: Border(right: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildNavItem(context, Icons.dashboard, 'Live Dashboard', true, () {}),
              _buildNavItem(context, Icons.people, 'Staff Directory', false, () => context.go('/staff')),
              _buildNavItem(context, Icons.calendar_month, 'Rosters & Scheduling', false, () => context.go('/rosters')),
              _buildNavItem(context, Icons.beach_access, 'Leave Management', false, () => context.go('/leave')),
              _buildNavItem(context, Icons.location_on, 'Geofence Zones', false, () {}),
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
          color: isSelected ? theme.colorScheme.primary.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: theme.colorScheme.primary.withOpacity(0.3)) : null,
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

  Widget _buildStaffView(BuildContext context, WidgetRef ref) {
    return Center(
      child: PremiumCard(
        blurRadius: 30,
        opacity: 0.1,
        child: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fingerprint, size: 80, color: Theme.of(context).colorScheme.primary)
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 2.seconds),
              const SizedBox(height: 24),
              Text('Secure Terminal', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Geofenced Biometric & QR Verification.', style: TextStyle(color: Colors.white60)),
              const SizedBox(height: 48),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    child: AnimatedButton(
                      text: 'GPS CLOCK IN',
                      onPressed: () => _handleGPSClockIn(ref),
                    ),
                  ),
                  const SizedBox(width: 24),
                  SizedBox(
                    width: 180,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF00E5FF)),
                      label: const Text('SCAN QR'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF00E5FF),
                        side: BorderSide(color: const Color(0xFF00E5FF).withOpacity(0.5)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                      ),
                      onPressed: () => _showQRScanner(context, ref),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text('CLOCK OUT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onPressed: () {
                     ref.read(clockServiceProvider).simulateClockEvent('clock_out');
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Clock Out recorded.')));
                  },
                ),
              )
            ],
          ),
        ),
      ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack),
    );
  }

  Future<void> _handleGPSClockIn(WidgetRef ref) async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location services are disabled.')));
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are denied')));
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permissions are permanently denied.')));
      return;
    } 

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verifying location...')));
    Position position = await Geolocator.getCurrentPosition();
    
    // In production, we'd check `position` against site boundaries.
    // Here we proceed to clock in.
    ref.read(clockServiceProvider).simulateClockEvent('clock_in');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS Verified. Clocked in at ${position.latitude.toStringAsFixed(2)}, ${position.longitude.toStringAsFixed(2)}')));
  }

  void _showQRScanner(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFF00E5FF), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                children: [
                  MobileScanner(
                    onDetect: (capture) {
                      final List<Barcode> barcodes = capture.barcodes;
                      if (barcodes.isNotEmpty) {
                        Navigator.pop(dialogContext);
                        ref.read(clockServiceProvider).simulateClockEvent('clock_in');
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('QR Verified. Clocked In.')));
                      }
                    },
                  ),
                  const Center(
                    child: Icon(Icons.qr_code_scanner, size: 80, color: Colors.white24),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(dialogContext),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildManagerView(BuildContext context, WidgetRef ref, AsyncValue activeExceptionsAsync) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDashboardHeader(activeExceptionsAsync).animate().fadeIn().slideY(begin: -0.2, end: 0),
        const SizedBox(height: 32),
        Expanded(
          child: activeExceptionsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading exceptions: $err', style: const TextStyle(color: Colors.white))),
            data: (exceptions) {
              if (exceptions.isEmpty) return _buildEmptyState();
              
              return ListView.builder(
                itemCount: exceptions.length,
                itemBuilder: (context, index) {
                  return _buildExceptionRow(context, ref, exceptions[index])
                      .animate()
                      .fadeIn(delay: (50 * index).ms)
                      .slideX(begin: 0.1, end: 0);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDashboardHeader(AsyncValue activeExceptionsAsync) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Actionable Exceptions',
              style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Real-time workforce compliance monitoring',
              style: TextStyle(color: Colors.white60),
            )
          ],
        ),
        activeExceptionsAsync.when(
          data: (exceptions) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: exceptions.isNotEmpty ? Colors.orange.withOpacity(0.15) : Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: exceptions.isNotEmpty ? Colors.orange.withOpacity(0.5) : Colors.green.withOpacity(0.5)),
              boxShadow: [
                 if (exceptions.isNotEmpty)
                    BoxShadow(color: Colors.orange.withOpacity(0.2), blurRadius: 20, spreadRadius: -5)
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
                  '${exceptions.length} Pending',
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
          error: (_, __) => const SizedBox(),
        ),
      ],
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
              color: Colors.green.withOpacity(0.1),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.2), blurRadius: 40)],
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

  Widget _buildExceptionRow(BuildContext context, WidgetRef ref, dynamic ex) {
    final theme = Theme.of(context);
    final isHighSeverity = ex.severity == 'high' || ex.severity == 'critical';
    final severityColor = isHighSeverity ? theme.colorScheme.error : Colors.orangeAccent;

    final isResolving = _resolvingExceptionId == ex.id;
    final hasSuggestion = _aiSuggestion != null && _resolvingExceptionId == ex.id;

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
                  height: 60,
                  decoration: BoxDecoration(
                    color: severityColor,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [BoxShadow(color: severityColor.withOpacity(0.5), blurRadius: 10)],
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
                            ex.exceptionType.replaceAll('_', ' ').toUpperCase(),
                            style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: severityColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: severityColor.withOpacity(0.5)),
                            ),
                            child: Text(
                              ex.severity.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: severityColor, letterSpacing: 1),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(ex.description ?? '', style: const TextStyle(color: Colors.white70, fontSize: 15)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.person_outline, size: 16, color: Colors.white38),
                          const SizedBox(width: 6),
                          Text(ex.employeeId.substring(0, 8), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                          const SizedBox(width: 24),
                          Icon(Icons.access_time, size: 16, color: Colors.white38),
                          const SizedBox(width: 6),
                          const Text('Logged Today', style: TextStyle(fontSize: 12, color: Colors.white54)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (ex.status == 'pending' && !isHighSeverity)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                        label: Row(
                          children: [
                            const Text('AI Suggestion', style: TextStyle(color: Color(0xFF7C3AED), fontWeight: FontWeight.bold)),
                          ],
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF7C3AED).withOpacity(0.5)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () => _simulateAIResolve(ex.id),
                      ),
                    if (ex.status == 'pending' && isHighSeverity)
                       FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: severityColor.withOpacity(0.2),
                          foregroundColor: severityColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: severityColor.withOpacity(0.5)),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                        ),
                        onPressed: () => ref.read(exceptionServiceProvider).resolveException(ex.id),
                        child: const Text('Review Required', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
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
                     color: const Color(0xFF7C3AED).withOpacity(0.1),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
                   ),
                   child: Row(
                     children: const [
                       SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF))),
                       SizedBox(width: 16),
                       Text('Synthesizing historical patterns...', style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
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
                     color: const Color(0xFF7C3AED).withOpacity(0.15),
                     borderRadius: BorderRadius.circular(16),
                     border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.5)),
                     boxShadow: [BoxShadow(color: const Color(0xFF7C3AED).withOpacity(0.1), blurRadius: 20)],
                   ),
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                       Row(
                         children: [
                           const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 20),
                           const SizedBox(width: 12),
                           const Text('AI Resolution Complete', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
                         ],
                       ),
                       const SizedBox(height: 12),
                       Text(_aiSuggestion!, style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.5)),
                       const SizedBox(height: 24),
                       Row(
                         children: [
                           SizedBox(
                             width: 160,
                             height: 48,
                             child: AnimatedButton(
                               text: 'Approve',
                               onPressed: () {
                                 ref.read(exceptionServiceProvider).resolveException(ex.id);
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

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted && _resolvingExceptionId == exceptionId) {
        setState(() {
          _aiSuggestion = "Historical analysis indicates this employee clocks out late on Fridays due to site closing duties. The XGBoost fraud model scored this as 0% risk. Recommendation: Approve overtime automatically.";
        });
      }
    });
  }
}
