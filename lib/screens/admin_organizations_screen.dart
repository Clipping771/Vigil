import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/ui_kit.dart';

const _plans = {'freemium': 'Free', 'pro': 'Pro', 'enterprise': 'Enterprise'};

/// Tenant management for system administrators.
class AdminOrganizationsScreen extends ConsumerStatefulWidget {
  const AdminOrganizationsScreen({super.key});

  @override
  ConsumerState<AdminOrganizationsScreen> createState() => _AdminOrganizationsScreenState();
}

class _AdminOrganizationsScreenState extends ConsumerState<AdminOrganizationsScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _failed = false;
  List<Map<String, dynamic>> _orgs = [];

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
      final res = await _db.from('organizations').select('*, employees(count)').order('created_at', ascending: false);
      if (mounted) setState(() => _orgs = List<Map<String, dynamic>>.from(res));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int _memberCount(Map<String, dynamic> org) {
    final e = org['employees'];
    if (e is List && e.isNotEmpty && e.first is Map) return (e.first['count'] as num?)?.toInt() ?? 0;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final pad = isCompact(context) ? 16.0 : 32.0;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'admin-add-org',
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add_business_outlined),
        label: const Text('Add organization'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 96),
          children: [
            ResponsiveGrid(
              minItemWidth: 150,
              children: [
                StatTile(icon: Icons.business_outlined, label: 'Organizations', value: '${_orgs.length}', tone: Tone.primary),
                StatTile(
                  icon: Icons.groups_outlined,
                  label: 'Total users',
                  value: '${_orgs.fold<int>(0, (s, o) => s + _memberCount(o))}',
                  tone: Tone.info,
                ),
                StatTile(
                  icon: Icons.workspace_premium_outlined,
                  label: 'Paid plans',
                  value: '${_orgs.where((o) => o['subscription_plan'] != 'freemium').length}',
                  tone: Tone.success,
                ),
              ],
            ),
            const SectionHeader('All organizations'),
            if (_loading)
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
            else if (_failed)
              Card(child: EmptyState(icon: Icons.cloud_off_outlined, title: 'Could not load organizations', action: OutlinedButton(onPressed: _load, child: const Text('Try again'))))
            else if (_orgs.isEmpty)
              const Card(child: EmptyState(icon: Icons.business_outlined, title: 'No organizations yet'))
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < _orgs.length; i++) ...[
                      if (i > 0) const Divider(indent: 72),
                      Builder(builder: (context) {
                        final o = _orgs[i];
                        final plan = o['subscription_plan'] ?? 'freemium';
                        final created = DateTime.tryParse(o['created_at']?.toString() ?? '');
                        final members = _memberCount(o);
                        return ListTile(
                          contentPadding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                          leading: CircleAvatar(
                            backgroundColor: cs.secondaryContainer,
                            child: Icon(Icons.business_outlined, color: cs.onSecondaryContainer),
                          ),
                          title: Text(o['name'] ?? '', style: t.titleSmall),
                          subtitle: Text(
                            '$members ${members == 1 ? 'member' : 'members'}${created != null ? '  ·  Joined ${DateFormat('d MMM yyyy').format(created.toLocal())}' : ''}',
                            style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StatusChip(_plans[plan] ?? plan, tone: plan == 'enterprise' ? Tone.primary : (plan == 'pro' ? Tone.success : Tone.neutral)),
                              PopupMenuButton<String>(
                                tooltip: 'More',
                                onSelected: (v) => v == 'edit' ? _edit(o) : _delete(o),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
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

  Future<void> _edit(Map<String, dynamic>? org) async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: org?['name']);
    var plan = (org?['subscription_plan'] as String?) ?? 'freemium';
    var saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(org == null ? 'Add organization' : 'Edit organization'),
          content: SizedBox(
            width: 420,
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Organization name'),
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a name' : null,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: plan,
                    decoration: const InputDecoration(labelText: 'Plan'),
                    items: [for (final e in _plans.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setLocal(() => plan = v ?? plan),
                  ),
                ],
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
                      try {
                        final data = {'name': name.text.trim(), 'subscription_plan': plan};
                        if (org == null) {
                          await _db.from('organizations').insert(data);
                        } else {
                          await _db.from('organizations').update(data).eq('id', org['id']);
                        }
                        if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                        if (mounted) showMessage(this.context, org == null ? 'Organization added.' : 'Changes saved.');
                        _load();
                      } catch (_) {
                        setLocal(() => saving = false);
                        if (mounted) showMessage(this.context, 'Could not save the organization.');
                      }
                    },
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(org == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
  }

  Future<void> _delete(Map<String, dynamic> org) async {
    final ok = await confirmDialog(
      context,
      title: 'Delete ${org['name']}?',
      message: 'All of its users, shifts, punches and leave records will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _db.from('organizations').delete().eq('id', org['id']);
      if (mounted) showMessage(context, 'Organization deleted.');
      _load();
    } catch (_) {
      if (mounted) showMessage(context, 'Could not delete the organization.');
    }
  }
}
