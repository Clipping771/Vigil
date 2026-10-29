import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/auth_layout.dart' show validateEmail;
import '../widgets/ui_kit.dart';

const _roles = ['owner', 'admin', 'hr', 'manager', 'staff', 'system_admin'];

/// Platform-wide user management for system administrators.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _users = [];
  Map<String, String> _orgNames = {};
  String _query = '';
  String? _orgFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final users = await _db.from('employees').select().order('full_name');
      final orgs = await _db.from('organizations').select('id, name').order('name');
      if (!mounted) return;
      setState(() {
        _users = List<Map<String, dynamic>>.from(users);
        _orgNames = {for (final o in orgs) o['id'] as String: o['name'] as String};
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final me = ref.watch(authProvider).currentUser;
    final pad = isCompact(context) ? 16.0 : 32.0;

    final visible = _users.where((u) {
      if (_orgFilter != null && u['organization_id'] != _orgFilter) return false;
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return '${u['full_name']} ${u['email']}'.toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-add-user',
        onPressed: _orgNames.isEmpty ? null : () => _editUser(null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add user'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 96),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: isCompact(context) ? double.infinity : 320,
                  child: SearchBar(
                    hintText: 'Search name or email',
                    leading: const Icon(Icons.search),
                    elevation: const WidgetStatePropertyAll(0),
                    side: WidgetStatePropertyAll(BorderSide(color: cs.outline)),
                    backgroundColor: WidgetStatePropertyAll(cs.surface),
                    constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                    onChanged: (v) => setState(() => _query = v.trim()),
                  ),
                ),
                SizedBox(
                  width: isCompact(context) ? double.infinity : 260,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _orgFilter,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Organization', isDense: true),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All organizations')),
                      for (final e in _orgNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => setState(() => _orgFilter = v),
                  ),
                ),
                Text('${visible.length} users', style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_failed)
              Card(child: EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load users', action: OutlinedButton(onPressed: _load, child: const Text('Try again'))))
            else if (visible.isEmpty)
              const Card(child: EmptyState(icon: Icons.person_search_outlined, title: 'No users found'))
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < visible.length; i++) ...[
                      if (i > 0) const Divider(indent: 72),
                      Builder(builder: (context) {
                        final u = visible[i];
                        final isMe = u['id'] == me?.id;
                        return ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                          leading: UserAvatar(name: u['full_name'] ?? '?', radius: 20),
                          title: Text(u['full_name'] ?? '', style: t.titleSmall),
                          subtitle: Text(
                            '${u['email']}  ·  ${_orgNames[u['organization_id']] ?? 'Unknown organization'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!isCompact(context))
                                StatusChip(roleLabel(u['role'] ?? 'staff'),
                                    tone: u['role'] == 'system_admin' ? Tone.danger : (const {'owner', 'admin'}.contains(u['role']) ? Tone.primary : Tone.neutral)),
                              if (u['auth_user_id'] == null && !isCompact(context)) ...[
                                const SizedBox(width: 8),
                                const Tooltip(message: 'Invited — has not signed in yet', child: StatusChip('Invited', tone: Tone.warning)),
                              ],
                              PopupMenuButton<String>(
                                tooltip: 'More',
                                onSelected: (v) => v == 'edit' ? _editUser(u) : _delete(u),
                                itemBuilder: (_) => [
                                  const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                                  if (!isMe)
                                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editUser(Map<String, dynamic>? user) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: user?['full_name']);
    final email = TextEditingController(text: user?['email']);
    final site = TextEditingController(text: user?['site_location']);
    var role = (user?['role'] as String?) ?? 'admin';
    var org = (user?['organization_id'] as String?) ?? _orgFilter ?? _orgNames.keys.first;
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(user == null ? 'Add user' : 'Edit user'),
          content: SizedBox(
            width: 440,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: name,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Full name'),
                      validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: email,
                      enabled: user == null,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: org,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Organization'),
                      items: [for (final e in _orgNames.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                      onChanged: (v) => setLocal(() => org = v ?? org),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Role'),
                      items: [for (final r in _roles) DropdownMenuItem(value: r, child: Text(roleLabel(r)))],
                      onChanged: (v) => setLocal(() => role = v ?? role),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(controller: site, decoration: const InputDecoration(labelText: 'Site (optional)')),
                    if (user == null) ...[
                      const SizedBox(height: 16),
                      Text('They join by choosing "Activate your account" on the sign-in page with this email.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: saving ? null : () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      setLocal(() => saving = true);
                      final data = {
                        'full_name': name.text.trim(),
                        'role': role,
                        'organization_id': org,
                        'site_location': site.text.trim().isEmpty ? null : site.text.trim(),
                      };
                      try {
                        if (user == null) {
                          await _db.from('employees').insert({...data, 'email': email.text.trim().toLowerCase()});
                        } else {
                          await _db.from('employees').update(data).eq('id', user['id']);
                        }
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (mounted) showMessage(this.context, user == null ? 'User added.' : 'Changes saved.');
                        _load();
                      } catch (e) {
                        setLocal(() => saving = false);
                        final msg = e is PostgrestException && e.code == '23505'
                            ? 'A user with this email already exists in that organization.'
                            : 'Could not save. ${e is PostgrestException ? e.message : ''}';
                        if (mounted) showMessage(this.context, msg);
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(user == null ? 'Add user' : 'Save'),
            ),
          ],
        ),
      ),
    );
    for (final c in [name, email, site]) {
      c.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${user['full_name']}?',
      message: 'Their shifts, punches and leave history will also be deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _db.from('employees').delete().eq('id', user['id']);
      if (mounted) showMessage(context, 'User deleted.');
      _load();
    } catch (_) {
      if (mounted) showMessage(context, 'Could not delete this user.');
    }
  }
}
