import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AdminOrganizationsScreen extends ConsumerStatefulWidget {
  const AdminOrganizationsScreen({super.key});

  @override
  ConsumerState<AdminOrganizationsScreen> createState() => _AdminOrganizationsScreenState();
}

class _AdminOrganizationsScreenState extends ConsumerState<AdminOrganizationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _organizations = [];
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _fetchOrganizations();
  }

  Future<void> _fetchOrganizations() async {
    setState(() => _isLoading = true);
    try {
      final response = await _supabase.from('organizations').select().order('created_at', ascending: false);
      setState(() {
        _organizations = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading organizations: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddOrganizationDialog() async {
    final nameController = TextEditingController();
    String selectedPlan = 'pro';
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text('Add Organization', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Organization Name',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedPlan,
                      dropdownColor: const Color(0xFF1F2937),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Subscription Plan',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'freemium', child: Text('Freemium')),
                        DropdownMenuItem(value: 'pro', child: Text('Pro')),
                        DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedPlan = val);
                      },
                    ),
                  ],
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
                      await _supabase.from('organizations').insert({
                        'id': const Uuid().v4(),
                        'name': nameController.text.trim(),
                        'subscription_plan': selectedPlan,
                      });
                      if (mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save Organization'),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) _fetchOrganizations();
    });
  }

  Future<void> _showEditOrganizationDialog(Map<String, dynamic> org) async {
    final nameController = TextEditingController(text: org['name']);
    String selectedPlan = org['subscription_plan'] ?? 'pro';
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1F2937),
              title: const Text('Edit Organization', style: TextStyle(color: Colors.white)),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Organization Name',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: selectedPlan,
                      dropdownColor: const Color(0xFF1F2937),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Subscription Plan',
                        labelStyle: const TextStyle(color: Colors.white70),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'freemium', child: Text('Freemium')),
                        DropdownMenuItem(value: 'pro', child: Text('Pro')),
                        DropdownMenuItem(value: 'enterprise', child: Text('Enterprise')),
                      ],
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedPlan = val);
                      },
                    ),
                  ],
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
                      await _supabase.from('organizations').update({
                        'name': nameController.text.trim(),
                        'subscription_plan': selectedPlan,
                      }).eq('id', org['id']);
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
      if (result == true) _fetchOrganizations();
    });
  }

  Future<void> _deleteOrganization(String id) async {
    try {
      await _supabase.from('organizations').delete().eq('id', id);
      _fetchOrganizations();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Organization deleted')));
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
                  const Text('Organizations', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text('Manage tenant organizations and billing plans.', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add Organization', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _showAddOrganizationDialog,
              )
            ],
          ),
          const SizedBox(height: 40),
          Expanded(
            child: _organizations.isEmpty 
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
                              const Color(0xFF8B5CF6).withOpacity(0.05),
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
                        child: Icon(Icons.business_outlined, size: 48, color: const Color(0xFF60A5FA).withOpacity(0.8)),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No Organizations Yet',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white.withOpacity(0.9)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Get started by creating your first tenant organization.',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Create Organization', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: _showAddOrganizationDialog,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
              itemCount: _organizations.length,
              itemBuilder: (context, index) {
                final org = _organizations[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.business, color: Color(0xFF60A5FA)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(org['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.white)),
                              const SizedBox(height: 4),
                              Text('ID: ${org['id']}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13)),
                            ],
                          ),
                        ),
                        _buildBadge(org['subscription_plan'] ?? 'pro'),
                        const SizedBox(width: 32),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white54),
                          onPressed: () => _showEditOrganizationDialog(org),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                          onPressed: () => _deleteOrganization(org['id']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }

  Widget _buildBadge(String plan) {
    final isEnterprise = plan.toLowerCase() == 'enterprise';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isEnterprise ? const Color(0xFF8B5CF6).withOpacity(0.15) : const Color(0xFF10B981).withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isEnterprise ? const Color(0xFF8B5CF6).withOpacity(0.3) : const Color(0xFF10B981).withOpacity(0.3)),
      ),
      child: Text(
        plan.toUpperCase(),
        style: TextStyle(
          color: isEnterprise ? const Color(0xFFA78BFA) : const Color(0xFF34D399),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
