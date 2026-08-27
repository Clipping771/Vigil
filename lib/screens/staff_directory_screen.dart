import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/staff_provider.dart';
import '../providers/auth_provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class StaffDirectoryScreen extends ConsumerStatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  ConsumerState<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends ConsumerState<StaffDirectoryScreen> {
  Future<void> _showAddStaffDialog() async {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final siteController = TextEditingController();
    String selectedRole = 'staff';
    bool isSaving = false;

    // Get the current company_admin's organization_id from Riverpod auth state
    final currentUser = ref.read(authProvider).currentUser;
    if (currentUser == null) return;
    
    final String orgId = currentUser.organizationId!;

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Staff Member'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                        items: const [
                          DropdownMenuItem(value: 'staff', child: Text('Staff')),
                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedRole = val);
                        },
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: siteController,
                        decoration: const InputDecoration(labelText: 'Site Location', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: isSaving ? null : () async {
                    if (nameController.text.trim().isEmpty || emailController.text.trim().isEmpty) return;
                    setDialogState(() => isSaving = true);
                    
                    try {
                      final fakeId = const Uuid().v4();
                      await Supabase.instance.client.from('employees').insert({
                        'id': fakeId,
                        'email': emailController.text.trim(),
                        'full_name': nameController.text.trim(),
                        'role': selectedRole,
                        'organization_id': orgId,
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
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add Staff'),
                ),
              ],
            );
          }
        );
      },
    ).then((result) {
      if (result == true) ref.refresh(staffProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Directory'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.refresh(staffProvider),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Add Staff'),
            onPressed: _showAddStaffDialog,
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'SecureLock Global Workforce',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: staffAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
                data: (staff) {
                  if (staff.isEmpty) {
                    return const Center(child: Text('No employees found in the database.'));
                  }
                  
                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 350,
                      childAspectRatio: 2.5,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: staff.length,
                    itemBuilder: (context, index) {
                      final employee = staff[index];
                      return Card(
                        elevation: 1,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                radius: 24,
                                child: Text(
                                  employee.fullName.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      employee.fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${employee.role.toUpperCase()} • ${employee.siteLocation ?? 'No Site Assigned'}',
                                      style: TextStyle(
                                        color: Colors.grey[700],
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      employee.email,
                                      style: TextStyle(
                                        color: Colors.grey[500],
                                        fontSize: 11,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
