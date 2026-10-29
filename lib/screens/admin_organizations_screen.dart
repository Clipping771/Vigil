import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/ui.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
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
              backgroundColor: context.surfaceHigh,
              title: Text('Add Organization', style: TextStyle(color: context.fg())),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: context.fg()),
                      decoration: InputDecoration(
                        labelText: 'Organization Name',
                        labelStyle: TextStyle(color: context.fg(0.7)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPlan,
                      dropdownColor: context.surfaceHigh,
                      style: TextStyle(color: context.fg()),
                      decoration: InputDecoration(
                        labelText: 'Subscription Plan',
                        labelStyle: TextStyle(color: context.fg(0.7)),
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
                  child: Text('Cancel', style: TextStyle(color: context.fg(0.54))),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B82F6)),
                  onPressed: isSaving ? null : () async {
                    if (nameController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      await _supabase.from('organizations').insert({
                        'name': nameController.text.trim(),
                        'subscription_plan': selectedPlan,
                      });
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg()))
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
              backgroundColor: context.surfaceHigh,
              title: Text('Edit Organization', style: TextStyle(color: context.fg())),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      style: TextStyle(color: context.fg()),
                      decoration: InputDecoration(
                        labelText: 'Organization Name',
                        labelStyle: TextStyle(color: context.fg(0.7)),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPlan,
                      dropdownColor: context.surfaceHigh,
                      style: TextStyle(color: context.fg()),
                      decoration: InputDecoration(
                        labelText: 'Subscription Plan',
                        labelStyle: TextStyle(color: context.fg(0.7)),
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
                  child: Text('Cancel', style: TextStyle(color: context.fg(0.54))),
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
                      if (context.mounted) Navigator.of(context).pop(true);
                    } catch (e) {
                      setDialogState(() => isSaving = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
                      }
                    }
                  },
                  child: isSaving 
                    ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: context.fg()))
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete organization?'),
        content: const Text('All of its employees and data will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _supabase.from('organizations').delete().eq('id', id);
      _fetchOrganizations();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Organization deleted')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Something went wrong. Please try again.'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 700 ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Organizations', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: context.fg())),
                  const SizedBox(height: 4),
                  Text('Manage tenant organizations and billing plans.', style: TextStyle(color: context.fg().withValues(alpha: 0.6))),
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
          const SizedBox(height: 24),
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
                              const Color(0xFF3B82F6).withValues(alpha: 0.1),
                              const Color(0xFF8B5CF6).withValues(alpha: 0.05),
                            ],
                          ),
                          border: Border.all(color: context.fg().withValues(alpha: 0.05)),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                              blurRadius: 40,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: Icon(Icons.business_outlined, size: 48, color: const Color(0xFF3B82F6).withValues(alpha: 0.8)),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'No Organizations Yet',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.fg().withValues(alpha: 0.9)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Get started by creating your first tenant organization.',
                        style: TextStyle(color: context.fg().withValues(alpha: 0.5), fontSize: 14),
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
                    color: context.surfaceHigh,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.fg().withValues(alpha: 0.05)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
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
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.business, color: Color(0xFF3B82F6)),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(org['name'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: context.fg())),
                              const SizedBox(height: 4),
                              Text('ID: ${org['id']}', style: TextStyle(color: context.fg().withValues(alpha: 0.5), fontSize: 13)),
                            ],
                          ),
                        ),
                        _buildBadge(org['subscription_plan'] ?? 'pro'),
                        const SizedBox(width: 32),
                        IconButton(
                          icon: Icon(Icons.edit, color: context.fg(0.54)),
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
        color: isEnterprise ? const Color(0xFF8B5CF6).withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isEnterprise ? const Color(0xFF8B5CF6).withValues(alpha: 0.3) : const Color(0xFF10B981).withValues(alpha: 0.3)),
      ),
      child: Text(
        plan.toUpperCase(),
        style: TextStyle(
          color: isEnterprise ? const Color(0xFF8B5CF6) : const Color(0xFF34D399),
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
