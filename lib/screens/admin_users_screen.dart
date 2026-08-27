import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../widgets/premium_card.dart';
import '../widgets/animated_button.dart';
import 'package:uuid/uuid.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _organizations = [];
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final userResponse = await _supabase.from('employees').select().order('created_at', ascending: false);
      final orgResponse = await _supabase.from('organizations').select();
      
      setState(() {
        _users = List<Map<String, dynamic>>.from(userResponse);
        _organizations = List<Map<String, dynamic>>.from(orgResponse);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading users: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddUserDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final siteController = TextEditingController();
    String selectedRole = 'manager';
    String? selectedOrg = _organizations.isNotEmpty ? _organizations.first['id'] : null;
    bool isSaving = false;

    if (_organizations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please create an organization first.')));
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text('Add System User', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Email Address',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: 'admin',
                        dropdownColor: const Color(0xFF1F2937),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Role',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Company Admin')),
                        ],
                        onChanged: null, // Locked for System Admin
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedOrg,
                        dropdownColor: const Color(0xFF1F2937),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Organization',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: _organizations.map<DropdownMenuItem<String>>((org) {
                          return DropdownMenuItem<String>(
                            value: org['id'],
                            child: Text(org['name']),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedOrg = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: siteController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Site Location (Optional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('Note: In this UI prototype, adding a user bypasses auth credential creation. They will appear in the directory but cannot log in without a real Supabase Auth record.', style: TextStyle(color: Colors.orangeAccent, fontSize: 11, fontStyle: FontStyle.italic)),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: isSaving ? null : () async {
                    if (nameController.text.trim().isEmpty || emailController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      // Simulating user creation for prototype
                      final fakeId = const Uuid().v4();
                      
                      await _supabase.from('employees').insert({
                        'id': fakeId,
                        'email': emailController.text.trim(),
                        'full_name': nameController.text.trim(),
                        'role': 'admin',
                        'organization_id': selectedOrg,
                        'site_location': siteController.text.trim().isEmpty ? null : siteController.text.trim(),
                      });
                      
                      if (mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to add: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Add User'),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) _fetchData();
    });
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final nameController = TextEditingController(text: user['full_name']);
    final emailController = TextEditingController(text: user['email']);
    final siteController = TextEditingController(text: user['site_location'] ?? '');
    String selectedRole = user['role'] ?? 'staff';
    String? selectedOrg = user['organization_id'];
    bool isSaving = false;

    if (_organizations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please create an organization first.')));
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text('Edit System User', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Full Name',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        style: const TextStyle(color: Colors.white),
                        enabled: false, // Cannot edit email in this simplified view without full auth api access
                        decoration: InputDecoration(
                          labelText: 'Email Address (Cannot Edit)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: 'admin',
                        dropdownColor: const Color(0xFF1F2937),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Role',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Company Admin')),
                        ],
                        onChanged: null, // Locked for System Admin
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedOrg,
                        dropdownColor: const Color(0xFF1F2937),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Organization',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: _organizations.map<DropdownMenuItem<String>>((org) {
                          return DropdownMenuItem<String>(
                            value: org['id'],
                            child: Text(org['name']),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedOrg = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: siteController,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Site Location (Optional)',
                          labelStyle: const TextStyle(color: Colors.white70),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: isSaving ? null : () async {
                    if (nameController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      await _supabase.from('employees').update({
                        'full_name': nameController.text.trim(),
                        'role': 'admin',
                        'organization_id': selectedOrg,
                        'site_location': siteController.text.trim().isEmpty ? null : siteController.text.trim(),
                      }).eq('id', user['id']);
                      
                      if (mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Changes'),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) _fetchData();
    });
  }

  Future<void> _deleteUser(String id) async {
    try {
      await _supabase.from('employees').delete().eq('id', id);
      _fetchData();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('System Users', style: GoogleFonts.outfit(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Manage employees and global administrators across the platform.', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                ],
              ),
              Row(
                children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Add User', style: TextStyle(fontWeight: FontWeight.bold)),
                    onPressed: _showAddUserDialog,
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 160,
                    height: 48,
                    child: AnimatedButton(
                      text: 'Refresh Users',
                      onPressed: _fetchData,
                    ),
                  ),
                ],
              )
            ],
          ).animate().fadeIn().slideY(begin: -0.2, end: 0),
          const SizedBox(height: 40),
          Expanded(
            child: _users.isEmpty 
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF3B82F6).withOpacity(0.1),
                              const Color(0xFF10B981).withOpacity(0.05),
                            ],
                          ),
                          border: Border.all(color: Colors.white.withOpacity(0.05)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withOpacity(0.1),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(Icons.people_outline, size: 48, color: const Color(0xFF60A5FA).withOpacity(0.8)),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No System Users Yet',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Click "Add User" to manually create administrators or managers.',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: PremiumCard(
                    blurRadius: 10,
                    opacity: 0.05,
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [const Color(0xFF00E5FF).withOpacity(0.2), const Color(0xFF7C3AED).withOpacity(0.2)]),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.3)),
                          ),
                          child: const Icon(Icons.person, color: Color(0xFF00E5FF)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user['full_name'], style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text('${user['email']} • Org: ${user['organization_id'].toString().substring(0,8)}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                            ],
                          ),
                        ),
                        _buildBadge(user['role'] ?? 'staff'),
                        const SizedBox(width: 32),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white54),
                          onPressed: () => _showEditUserDialog(user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFFF3366)),
                          onPressed: () => _deleteUser(user['id']),
                        ),
                      ],
                    ),
                  ),
                ).animate().fadeIn(delay: (50 * index).ms).slideX(begin: 0.1, end: 0);
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBadge(String role) {
    bool isAdmin = role == 'system_admin';
    bool isManager = role == 'manager';
    
    Color textColor = isAdmin ? const Color(0xFFF87171) : (isManager ? const Color(0xFFFBBF24) : const Color(0xFF60A5FA));
    Color bgColor = isAdmin ? const Color(0xFFEF4444).withOpacity(0.15) : (isManager ? const Color(0xFFF59E0B).withOpacity(0.15) : const Color(0xFF3B82F6).withOpacity(0.15));
    Color borderColor = isAdmin ? const Color(0xFFEF4444).withOpacity(0.3) : (isManager ? const Color(0xFFF59E0B).withOpacity(0.3) : const Color(0xFF3B82F6).withOpacity(0.3));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        role.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
