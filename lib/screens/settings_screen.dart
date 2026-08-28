import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/reporting_engine.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final user = authState.currentUser;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Company Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/dashboard'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'My Profile',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 40,
                    child: Text(
                      user?.fullName.substring(0, 1).toUpperCase() ?? '?',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName ?? 'Unknown User',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('Email: ${user?.email ?? 'N/A'}'),
                      Text('Role: ${user?.role.toUpperCase() ?? 'N/A'}'),
                      Text('Organization ID: ${user?.organizationId.substring(0,8) ?? 'N/A'}'),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Compliance Rule Engine',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Adjust the thresholds that trigger exceptions across your organization.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            child: Column(
              children: [
                ListTile(
                  title: const Text('Late Clock-in Grace Period (Minutes)'),
                  subtitle: const Text('Allowed tardiness before marking exception'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: settings.allowedLateMinutes > 0 ? () {
                          ref.read(settingsProvider.notifier).updateLateMinutes(settings.allowedLateMinutes - 5);
                        } : null,
                      ),
                      Text('${settings.allowedLateMinutes} min', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          ref.read(settingsProvider.notifier).updateLateMinutes(settings.allowedLateMinutes + 5);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Max Overtime Threshold (Minutes)'),
                  subtitle: const Text('Allowed overtime before triggering exception'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: settings.allowedOvertimeMinutes > 0 ? () {
                          ref.read(settingsProvider.notifier).updateOvertimeMinutes(settings.allowedOvertimeMinutes - 15);
                        } : null,
                      ),
                      Text('${settings.allowedOvertimeMinutes} min', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () {
                          ref.read(settingsProvider.notifier).updateOvertimeMinutes(settings.allowedOvertimeMinutes + 15);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'AI Assistant Configuration',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Choose the generative AI model to power the Vigil Assistant.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('AI Provider', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Gemini', label: Text('Gemini'), icon: Icon(Icons.auto_awesome)),
                      ButtonSegment(value: 'ChatGPT', label: Text('ChatGPT'), icon: Icon(Icons.chat)),
                      ButtonSegment(value: 'Claude', label: Text('Claude'), icon: Icon(Icons.psychology)),
                    ],
                    selected: {settings.aiProvider},
                    onSelectionChanged: (Set<String> newSelection) {
                      ref.read(settingsProvider.notifier).updateAiProvider(newSelection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      selectedForegroundColor: Colors.white,
                      selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('${settings.aiProvider} API Key', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey(settings.aiProvider),
                    initialValue: settings.aiProvider == 'Gemini'
                        ? settings.geminiApiKey
                        : settings.aiProvider == 'ChatGPT'
                            ? settings.chatGptApiKey
                            : settings.claudeApiKey,
                    obscureText: true,
                    decoration: InputDecoration(
                      hintText: 'Enter your ${settings.aiProvider} API key',
                      border: const OutlineInputBorder(),
                      suffixIcon: const Icon(Icons.key),
                    ),
                    onChanged: (value) {
                      if (settings.aiProvider == 'Gemini') {
                        ref.read(settingsProvider.notifier).updateGeminiApiKey(value);
                      } else if (settings.aiProvider == 'ChatGPT') {
                        ref.read(settingsProvider.notifier).updateChatGptApiKey(value);
                      } else if (settings.aiProvider == 'Claude') {
                        ref.read(settingsProvider.notifier).updateClaudeApiKey(value);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: settings.isFetchingModels ? null : () async {
                      final scaffoldMessenger = ScaffoldMessenger.of(context);
                      try {
                        await ref.read(settingsProvider.notifier).fetchModels();
                        if (ref.read(settingsProvider).availableModels.isNotEmpty) {
                          scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Models fetched successfully')));
                        } else {
                          scaffoldMessenger.showSnackBar(const SnackBar(content: Text('No models found or API key invalid')));
                        }
                      } catch (e) {
                        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
                      }
                    },
                    icon: settings.isFetchingModels
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.download),
                    label: Text(settings.isFetchingModels ? 'Fetching Models...' : 'Fetch Models'),
                  ),
                  const SizedBox(height: 16),
                  if (settings.availableModels.isNotEmpty) ...[
                    const Text('Select Model', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: settings.availableModels.contains(settings.selectedModel) ? settings.selectedModel : null,
                      hint: const Text('Choose a model'),
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: settings.availableModels.map((model) {
                        return DropdownMenuItem(
                          value: model,
                          child: Text(model),
                        );
                      }).toList(),
                      onChanged: (value) {
                        ref.read(settingsProvider.notifier).updateSelectedModel(value);
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Automated Reporting Scheduler',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 1,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Enable Daily Auto-Export (5:00 PM)'),
                  subtitle: const Text('Automatically generates exception CSV and saves to Cloud.'),
                  value: settings.autoReportingEnabled,
                  onChanged: (val) {
                    ref.read(settingsProvider.notifier).toggleAutoReporting(val);
                    if (val) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auto-reporting enabled for 5:00 PM daily.')));
                    }
                  },
                ),
                if (settings.autoReportingEnabled)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Trigger Scheduled Job (Demo)'),
                      onPressed: () {
                        ReportingEngine().runScheduledReportDemo(context, user!.organizationId);
                      },
                    ),
                  )
              ],
            ),
          ),
          const SizedBox(height: 40),
          Center(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.logout),
              label: const Text('Sign Out'),
              onPressed: () {
                ref.read(authProvider.notifier).logout();
                context.go('/');
              },
            ),
          ),
        ],
      ),
    );
  }
}
