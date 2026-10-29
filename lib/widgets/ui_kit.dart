import 'package:flutter/material.dart';
import '../providers/theme_provider.dart';
import 'agent_fab.dart';
import 'app_shell.dart';

/// Semantic tone used by chips, stat tiles and banners.
enum Tone { neutral, primary, success, warning, danger, info }

extension ToneColors on Tone {
  /// (foreground, container) for this tone in the current theme.
  (Color, Color) colors(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = Theme.of(context).extension<StatusColors>()!;
    return switch (this) {
      Tone.neutral => (cs.onSurfaceVariant, cs.surfaceContainerHighest),
      Tone.primary => (cs.onSecondaryContainer, cs.secondaryContainer),
      Tone.success => (st.onSuccessContainer, st.successContainer),
      Tone.warning => (st.onWarningContainer, st.warningContainer),
      Tone.danger => (cs.onErrorContainer, cs.errorContainer),
      Tone.info => (st.onInfoContainer, st.infoContainer),
    };
  }

  /// Solid accent (icons, dots) for this tone.
  Color accent(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final st = Theme.of(context).extension<StatusColors>()!;
    return switch (this) {
      Tone.neutral => cs.onSurfaceVariant,
      Tone.primary => cs.primary,
      Tone.success => st.success,
      Tone.warning => st.warning,
      Tone.danger => cs.error,
      Tone.info => st.info,
    };
  }
}

bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).width < 700;

/// Standard signed-in page: top app bar, centred scrollable content.
class AppPage extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final List<Widget> children;
  final Widget? floatingActionButton;
  final double maxWidth;
  final PreferredSizeWidget? bottom;

  const AppPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.floatingActionButton,
    this.maxWidth = 1200,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    final pad = isCompact(context) ? 16.0 : 32.0;
    return Scaffold(
      appBar: AppBar(
        leading: ShellMenuButton.maybe(context),
        title: Text(title),
        actions: [...actions, const AiAssistantButton(), const SizedBox(width: 8)],
        bottom: bottom,
      ),
      floatingActionButton: floatingActionButton,
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, 8, pad, 96),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Title + optional subtitle and trailing actions for a section of a page.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const SectionHeader(this.title, {super.key, this.subtitle, this.actions = const [], this.padding = const EdgeInsets.only(top: 24, bottom: 12)});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 8,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: t.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ],
          ),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

/// Lays children out in equal columns that collapse on narrow widths.
class ResponsiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minItemWidth;
  final double spacing;

  const ResponsiveGrid({super.key, required this.children, this.minItemWidth = 240, this.spacing = 16});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / minItemWidth).floor().clamp(1, children.length.clamp(1, 99));
      final w = (c.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [for (final child in children) SizedBox(width: w, child: child)],
      );
    });
  }
}

/// Key metric tile: icon, label, big value, optional caption.
class StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? caption;
  final Tone tone;

  const StatTile({super.key, required this.icon, required this.label, required this.value, this.caption, this.tone = Tone.primary});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (fg, bg) = tone.colors(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: fg),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(value, style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w500)),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small rounded status label.
class StatusChip extends StatelessWidget {
  final String label;
  final Tone tone;
  final IconData? icon;

  const StatusChip(this.label, {super.key, this.tone = Tone.neutral, this.icon});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = tone.colors(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
        ],
      ),
    );
  }
}

/// Inline message strip (info / warning / error).
class InfoBanner extends StatelessWidget {
  final String message;
  final Tone tone;
  final IconData icon;
  final Widget? action;

  const InfoBanner(this.message, {super.key, this.tone = Tone.info, this.icon = Icons.info_outline, this.action});

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = tone.colors(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
          ?action,
        ],
      ),
    );
  }
}

/// Centered empty / error state.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: cs.onSecondaryContainer),
          ),
          const SizedBox(height: 16),
          Text(title, style: t.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 4),
            Text(message!, style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// Shows a confirm dialog; returns true when the user confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok == true;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
