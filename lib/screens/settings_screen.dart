import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../models/public_holiday.dart';
import '../providers/auth_provider.dart';
import '../providers/leave_calendar_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/ui_kit.dart';
import '../services/agent_service.dart';
import '../widgets/agent_fab.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(leading: ShellMenuButton.maybe(context), title: const Text('Settings'), actions: const [AiAssistantButton(), SizedBox(width: 8)]),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: EdgeInsets.all(compact ? 16 : 28),
            children: [
              const PageHeader(title: 'Settings', subtitle: 'Your profile, appearance and workspace preferences.'),
              const SizedBox(height: 24),
              _Section(
                title: 'Profile',
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      UserAvatar(name: user.fullName, radius: 28),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.fullName, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Text(user.email, style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              _Pill(roleLabel(user.role)),
                              if (user.siteLocation != null) _Pill(user.siteLocation!),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const _AppearanceSection(),
              if (user.isManager) const _ComplianceSection(),
              if (user.isManager) const _PublicHolidaysSection(),
              const _AiSection(),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
                  label: Text('Sign out', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  onPressed: () async {
                    await ref.read(authProvider.notifier).logout();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          Card(child: child),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeProvider).currentTheme;
    return _Section(
      title: 'Appearance',
      subtitle: 'Saved on this device.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SegmentedButton<AppTheme>(
              showSelectedIcon: false,
              segments: [
                for (final t in AppTheme.values) ButtonSegment(value: t, icon: Icon(t.icon), label: Text(t.label)),
              ],
              selected: {current},
              onSelectionChanged: (s) => ref.read(themeProvider.notifier).setTheme(s.first),
            ),
          ),
          SwitchListTile(
            value: ref.watch(complianceColorsProvider),
            onChanged: ref.read(complianceColorsProvider.notifier).set,
            title: const Text('Compliance alert colours'),
            subtitle: const Text('Turn the app amber or red while compliance issues are open. The banner still shows.'),
          ),
        ],
      ),
    );
  }
}

class _ComplianceSection extends ConsumerWidget {
  const _ComplianceSection();

  Future<void> _apply(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save. Only managers and admins can change compliance rules.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    Widget stepper(int value, int step, Future<void> Function(int) onChanged) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Decrease',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > 0 ? () => _apply(context, () => onChanged(value - step)) : null,
            ),
            SizedBox(
              width: 64,
              child: Text('$value min', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            IconButton(
              tooltip: 'Increase',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => _apply(context, () => onChanged(value + step)),
            ),
          ],
        );

    return _Section(
      title: 'Compliance rules',
      subtitle: 'Applies to everyone in your organization. Changes save automatically.',
      child: Column(
        children: [
          ListTile(
            title: const Text('Late clock-in grace period'),
            subtitle: const Text('Minutes after shift start before a late exception is raised'),
            trailing: stepper(settings.allowedLateMinutes, 5, notifier.updateLateMinutes),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('Overtime threshold'),
            subtitle: const Text('Minutes past shift end before an overtime exception is raised'),
            trailing: stepper(settings.allowedOvertimeMinutes, 15, notifier.updateOvertimeMinutes),
          ),
        ],
      ),
    );
  }
}

class _PublicHolidaysSection extends ConsumerWidget {
  const _PublicHolidaysSection();

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final organizationId = ref.read(authProvider).currentUser?.organizationId;
    if (organizationId == null) return;
    final name = TextEditingController();
    final now = DateTime.now();
    DateTime? date;

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setLocal) => AlertDialog(
          title: const Text('Add public holiday'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  maxLength: 100,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(date == null ? 'Choose date' : DateFormat('EEE, d MMM yyyy').format(date!)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialogCtx,
                      initialDate: date ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5, 12, 31),
                    );
                    if (picked != null) setLocal(() => date = picked);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: date == null || name.text.trim().isEmpty ? null : () => Navigator.pop(dialogCtx, true),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    final holidayName = name.text;
    name.dispose();
    if (save != true) return;

    try {
      await addPublicHoliday(organizationId: organizationId, date: date!, name: holidayName);
      ref.invalidate(publicHolidaysProvider);
    } on PostgrestException catch (e) {
      if (context.mounted) {
        showMessage(context, e.code == '23505' ? 'That date is already a public holiday.' : 'Could not add this public holiday.');
      }
    } catch (_) {
      if (context.mounted) showMessage(context, 'Could not add this public holiday.');
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, PublicHoliday holiday) async {
    final ok = await confirmDialog(
      context,
      title: 'Remove ${holiday.name}?',
      message: 'Leave on this date will use up leave balances again.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok) return;
    try {
      await removePublicHoliday(holiday.id);
      ref.invalidate(publicHolidaysProvider);
    } catch (_) {
      if (context.mounted) showMessage(context, 'Could not remove this public holiday.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final holidays = ref.watch(publicHolidaysProvider);
    final thisYear = DateTime(DateTime.now().year);
    final shown = (holidays.valueOrNull ?? const <PublicHoliday>[]).where((h) => !h.date.isBefore(thisYear)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return _Section(
      title: 'Public holidays',
      subtitle: 'Leave on these dates does not use up balances. Applies to everyone in your organization, so add the holidays for your state each year.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (holidays.hasError)
            const ListTile(leading: Icon(Icons.cloud_off_outlined), title: Text('Could not load public holidays'))
          else if (shown.isEmpty && !holidays.isLoading)
            const ListTile(title: Text('No public holidays added yet')),
          for (final h in shown)
            ListTile(
              title: Text(h.name),
              subtitle: Text(DateFormat('EEE, d MMM yyyy').format(h.date)),
              trailing: IconButton(
                tooltip: 'Remove ${h.name}',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(context, ref, h),
              ),
            ),
          const Divider(height: 1),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add public holiday'),
                onPressed: () => _add(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();

  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  bool _obscure = true;
  bool _testing = false;
  (bool ok, String message)? _result;

  static const _labels = {'Gemini': 'Gemini', 'ChatGPT': 'OpenAI', 'Claude': 'Claude', 'Ollama': 'Ollama'};

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final msg = await ref.read(agentServiceProvider).testConnection();
      if (mounted) setState(() => _result = (true, msg));
    } catch (e) {
      if (mounted) setState(() => _result = (false, e is AgentUnavailable ? e.message : 'Connection failed: $e'));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _loadModels() async {
    setState(() => _result = null);
    try {
      await ref.read(settingsProvider.notifier).fetchModels();
    } catch (e) {
      if (mounted) setState(() => _result = (false, e.toString().replaceFirst('Exception: ', '')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final isOllama = settings.aiProvider == 'Ollama';
    final label = _labels[settings.aiProvider] ?? settings.aiProvider;

    return _Section(
      title: 'AI assistant',
      subtitle: isOllama
          ? 'Runs on your own computer with Ollama — free, private, no API key.'
          : 'Bring your own API key. It stays only on this device until you sign out, and is sent directly to the provider.',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  for (final e in _labels.entries)
                    ButtonSegment(
                      value: e.key,
                      label: Text(e.value),
                      icon: e.key == 'Ollama' ? const Icon(Icons.computer_outlined, size: 18) : null,
                    ),
                ],
                selected: {settings.aiProvider},
                onSelectionChanged: (s) {
                  setState(() => _result = null);
                  notifier.updateAiProvider(s.first);
                },
              ),
            ),
            const SizedBox(height: 20),
            if (isOllama) ...[
              TextFormField(
                key: const ValueKey('ollama-url'),
                initialValue: settings.ollamaBaseUrl,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Ollama server URL',
                  prefixIcon: Icon(Icons.dns_outlined),
                  helperText: 'Default: $defaultOllamaUrl',
                ),
                onChanged: notifier.updateOllamaUrl,
              ),
              const SizedBox(height: 12),
              const InfoBanner(
                'Install Ollama from ollama.com, then run "ollama pull llama3.2". '
                'To use it from the website, start Ollama with OLLAMA_ORIGINS set to this site address (or *).',
                icon: Icons.lightbulb_outline,
              ),
            ] else
              TextFormField(
                key: ValueKey('key-${settings.aiProvider}'),
                initialValue: settings.activeApiKey,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: '$label API key',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show key' : 'Hide key',
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onChanged: (v) {
                  setState(() => _result = null);
                  notifier.updateApiKey(v);
                },
              ),
            const SizedBox(height: 16),
            if (settings.availableModels.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('${settings.aiProvider}|${settings.availableModels.length}'),
                initialValue: settings.availableModels.contains(settings.selectedModel) ? settings.selectedModel : null,
                isExpanded: true,
                hint: Text('Default: ${defaultAiModels[settings.aiProvider]}'),
                decoration: const InputDecoration(labelText: 'Model'),
                items: [for (final m in settings.availableModels) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: (m) {
                  setState(() => _result = null);
                  notifier.updateSelectedModel(m);
                },
              ),
              const SizedBox(height: 16),
            ],
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _testing ? null : _test,
                  icon: _testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 18),
                  label: Text(_testing ? 'Testing…' : 'Test connection'),
                ),
                OutlinedButton.icon(
                  onPressed: settings.isFetchingModels ? null : _loadModels,
                  icon: settings.isFetchingModels
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: Text(isOllama ? 'Load installed models' : 'Load models'),
                ),
                Text('Model: ${settings.activeModel}', style: theme.textTheme.bodySmall),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              InfoBanner(
                _result!.$2,
                tone: _result!.$1 ? Tone.success : Tone.danger,
                icon: _result!.$1 ? Icons.check_circle_outline : Icons.error_outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
