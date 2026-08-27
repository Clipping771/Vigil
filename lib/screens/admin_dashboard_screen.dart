import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../providers/auth_provider.dart';

import 'admin_organizations_screen.dart';
import 'admin_users_screen.dart';
import 'admin_database_viewer.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).currentUser;
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topLeft,
            radius: 1.5,
            colors: [
              Color(0xFF1E293B), // Lighter top left
              Color(0xFF0F172A), // Deep navy bottom right
              Color(0xFF020617), // Darkest corner
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Row(
          children: [
            // Glassmorphic Sidebar
            Container(
              width: 280,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.03),
                border: Border(
                  right: BorderSide(color: Colors.white.withOpacity(0.08)),
                ),
              ),
              child: Column(
                children: [
                  // Premium Header Area
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF3B82F6), Color(0xFF8B5CF6)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF3B82F6).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.shield, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vigil',
                                style: GoogleFonts.outfit(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              Text(
                                'Command Center',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: const Color(0xFF94A3B8),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 16),
                
                // Navigation Items
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildNavItem(0, Icons.domain, 'Organizations'),
                      const SizedBox(height: 4),
                      _buildNavItem(1, Icons.people, 'System Users'),
                      const SizedBox(height: 4),
                      _buildNavItem(2, Icons.table_chart, 'Database View'),
                    ],
                  ),
                ),
                
                // User Profile Footer
                const Divider(color: Colors.white12, height: 1),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFF3B82F6),
                        radius: 18,
                        child: Text(
                          user?.fullName.substring(0, 1).toUpperCase() ?? 'A',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? 'Admin User',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Super Admin',
                              style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white54, size: 20),
                        onPressed: () {
                          ref.read(authProvider.notifier).logout();
                          context.go('/');
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Main Content Area
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                bottomLeft: Radius.circular(24),
              ),
              child: Container(
                color: theme.scaffoldBackgroundColor, // Themed background
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

  Widget _buildNavItem(int index, IconData icon, String title) {
    final isSelected = _selectedIndex == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF3B82F6).withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          leading: Icon(icon, color: isSelected ? const Color(0xFF60A5FA) : Colors.white54, size: 22),
          title: Text(
            title,
            style: GoogleFonts.inter(
              color: isSelected ? Colors.white : Colors.white70,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
            ),
          ),
          selected: isSelected,
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return const AdminOrganizationsScreen();
      case 1:
        return const AdminUsersScreen();
      case 2:
        return const AdminDatabaseViewer();
      default:
        return const Center(child: Text('Unknown Module'));
    }
  }
}
