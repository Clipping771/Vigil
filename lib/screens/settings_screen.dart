import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/app_shell.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) return const SizedBox.shrink();
    final compact = MediaQuery.sizeOf(context).width < 700;

    return Scaffold(
      appBar: AppBar(leading: ShellMenuButton.maybe(context), title: const Text('Settings')),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SegmentedButton<AppTheme>(
          segments: [
            for (final t in AppTheme.values) ButtonSegment(value: t, icon: Icon(t.icon), label: Text(t.label)),
          ],
          selected: {current},
          onSelectionChanged: (s) => ref.read(themeProvider.notifier).setTheme(s.first),
        ),
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

class _AiSection extends ConsumerStatefulWidget {
  const _AiSection();

  @override
  ConsumerState<_AiSection> createState() => _AiSectionState();
}

class _AiSectionState extends ConsumerState<_AiSection> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return _Section(
      title: 'AI assistant',
      subtitle: 'Bring your own API key. It is stored only on this device and sent directly to the provider.',
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Gemini', label: Text('Gemini')),
                ButtonSegment(value: 'ChatGPT', label: Text('OpenAI')),
                ButtonSegment(value: 'Claude', label: Text('Claude')),
              ],
              selected: {settings.aiProvider},
              onSelectionChanged: (s) => notifier.updateAiProvider(s.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: ValueKey('key-${settings.aiProvider}'),
              initialValue: settings.activeApiKey,
              obscureText: _obscure,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: '${settings.aiProvider == 'ChatGPT' ? 'OpenAI' : settings.aiProvider} API key',
                prefixIcon: const Icon(Icons.key_outlined),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show key' : 'Hide key',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onChanged: notifier.updateApiKey,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: settings.isFetchingModels
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await notifier.fetchModels();
                          } catch (e) {
                            messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
                          }
                        },
                  icon: settings.isFetchingModels
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync, size: 18),
                  label: const Text('Load models'),
                ),
                Text('Using: ${settings.activeModel}', style: theme.textTheme.bodySmall),
              ],
            ),
            if (settings.availableModels.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('${settings.aiProvider}|${settings.availableModels.length}'),
                initialValue: settings.availableModels.contains(settings.selectedModel) ? settings.selectedModel : null,
                isExpanded: true,
                hint: const Text('Choose a model'),
                decoration: const InputDecoration(labelText: 'Model'),
                items: [for (final m in settings.availableModels) DropdownMenuItem(value: m, child: Text(m))],
                onChanged: notifier.updateSelectedModel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
