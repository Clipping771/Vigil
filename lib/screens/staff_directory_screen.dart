import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../providers/staff_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/auth_layout.dart' show validateEmail;

class StaffDirectoryScreen extends ConsumerStatefulWidget {
  const StaffDirectoryScreen({super.key});

  @override
  ConsumerState<StaffDirectoryScreen> createState() => _StaffDirectoryScreenState();
}

class _StaffDirectoryScreenState extends ConsumerState<StaffDirectoryScreen> {
  String _query = '';
  String _roleFilter = 'all';

  List<String> _assignableRoles(Employee me) =>
      me.isOrgAdmin ? const ['staff', 'manager', 'hr', 'admin'] : const ['staff', 'manager', 'hr'];

  String _friendlyError(Object e) {
    if (e is PostgrestException) {
      if (e.code == '23505') return 'Someone with this email is already in your organization.';
      return e.message;
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _showEmployeeDialog({Employee? existing}) async {
    final me = ref.read(authProvider).currentUser;
    if (me == null) return;

    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: existing?.fullName);
    final emailController = TextEditingController(text: existing?.email);
    final siteController = TextEditingController(text: existing?.siteLocation);
    final roles = _assignableRoles(me);
    String selectedRole = existing != null && roles.contains(existing.role) ? existing.role : 'staff';
    final canChangeRole = existing == null || (roles.contains(existing.role) && existing.id != me.id);
    bool isSaving = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            if (!(formKey.currentState?.validate() ?? false)) return;
            setDialogState(() => isSaving = true);
            final site = siteController.text.trim();
            try {
              final client = Supabase.instance.client;
              if (existing == null) {
                await client.from('employees').insert({
                  'email': emailController.text.trim().toLowerCase(),
                  'full_name': nameController.text.trim(),
                  'role': selectedRole,
                  'organization_id': me.organizationId,
                  'site_location': site.isEmpty ? null : site,
                });
              } else {
                await client.from('employees').update({
                  'full_name': nameController.text.trim(),
                  if (canChangeRole) 'role': selectedRole,
                  'site_location': site.isEmpty ? null : site,
                }).eq('id', existing.id);
              }
              if (context.mounted) Navigator.of(context).pop(true);
            } catch (e) {
              setDialogState(() => isSaving = false);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
              }
            }
          }

          return AlertDialog(
            title: Text(existing == null ? 'Invite team member' : 'Edit team member'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: nameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Full name'),
                        validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: emailController,
                        enabled: existing == null,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Work email'),
                        validator: validateEmail,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        initialValue: selectedRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: [for (final r in roles) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
                        onChanged: canChangeRole ? (v) => setDialogState(() => selectedRole = v ?? selectedRole) : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: siteController,
                        decoration: const InputDecoration(labelText: 'Site location (optional)'),
                      ),
                      if (existing == null) ...[
                        const SizedBox(height: 16),
                        Text(
                          'They can join by choosing "Activate your account" on the sign-in page with this email.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: isSaving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              FilledButton(
                onPressed: isSaving ? null : save,
                child: isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(existing == null ? 'Send invite' : 'Save changes'),
              ),
            ],
          );
        },
      ),
    );

    nameController.dispose();
    emailController.dispose();
    siteController.dispose();
    if (saved == true) ref.invalidate(staffProvider);
  }

  Future<void> _confirmRemove(Employee employee) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove team member?'),
        content: Text('${employee.fullName} will lose access and their shifts and history will be deleted. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Supabase.instance.client.from('employees').delete().eq('id', employee.id);
      ref.invalidate(staffProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Only owners and admins can remove team members.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final staffAsync = ref.watch(staffProvider);
    final me = ref.watch(authProvider).currentUser;
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(
        leading: ShellMenuButton.maybe(context),
        title: const Text('Staff'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => ref.invalidate(staffProvider)),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      body: Padding(
        padding: EdgeInsets.all(compact ? 16 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PageHeader(
              title: 'Team directory',
              subtitle: staffAsync.hasValue ? '${staffAsync.value!.length} people in your organization' : null,
              actions: [
                FilledButton.icon(
                  onPressed: () => _showEmployeeDialog(),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Invite member'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: compact ? double.infinity : 320,
                  child: TextField(
                    decoration: const InputDecoration(hintText: 'Search by name, email or site', prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                for (final r in const ['all', 'staff', 'manager', 'hr', 'admin', 'owner'])
                  ChoiceChip(
                    label: Text(r == 'all' ? 'All' : roleLabel(r)),
                    selected: _roleFilter == r,
                    onSelected: (_) => setState(() => _roleFilter = r),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Expanded(
              child: staffAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => _EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load your team',
                  action: OutlinedButton(onPressed: () => ref.invalidate(staffProvider), child: const Text('Try again')),
                ),
                data: (staff) {
                  final filtered = staff.where((e) {
                    if (_roleFilter != 'all' && e.role != _roleFilter) return false;
                    if (_query.isEmpty) return true;
                    return e.fullName.toLowerCase().contains(_query) ||
                        e.email.toLowerCase().contains(_query) ||
                        (e.siteLocation ?? '').toLowerCase().contains(_query);
                  }).toList();

                  if (filtered.isEmpty) {
                    return _EmptyState(
                      icon: Icons.group_off_outlined,
                      title: staff.isEmpty ? 'No team members yet' : 'No matches',
                      subtitle: staff.isEmpty ? 'Invite your first employee to get started.' : 'Try a different search or filter.',
                    );
                  }

                  return GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 380,
                      mainAxisExtent: 96,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final e = filtered[i];
                      final theme = Theme.of(context);
                      return Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _showEmployeeDialog(existing: e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                UserAvatar(name: e.fullName, radius: 22),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(e.fullName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                                      const SizedBox(height: 2),
                                      Text(e.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                                      const SizedBox(height: 4),
                                      Text(
                                        [roleLabel(e.role), if (e.siteLocation != null) e.siteLocation!].join(' · '),
                                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                                      ),
                                    ],
                                  ),
                                ),
                                if ((me?.isOrgAdmin ?? false) && e.id != me?.id && e.role != 'owner')
                                  PopupMenuButton<String>(
                                    tooltip: 'More',
                                    onSelected: (v) => v == 'edit' ? _showEmployeeDialog(existing: e) : _confirmRemove(e),
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      PopupMenuItem(value: 'remove', child: Text('Remove')),
                                    ],
                                  ),
                              ],
                            ),
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

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const _EmptyState({required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
