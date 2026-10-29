import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/employee.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';

class NavDestination {
  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final bool Function(Employee user) visibleTo;

  const NavDestination(this.path, this.label, this.icon, this.selectedIcon, this.visibleTo);
}

bool _everyone(Employee _) => true;
bool _managers(Employee u) => u.isManager;
bool _systemAdmins(Employee u) => u.isSystemAdmin;

const appDestinations = [
  NavDestination('/dashboard', 'Dashboard', Icons.space_dashboard_outlined, Icons.space_dashboard, _everyone),
  NavDestination('/rosters', 'Rosters', Icons.calendar_month_outlined, Icons.calendar_month, _everyone),
  NavDestination('/leave', 'Leave', Icons.event_available_outlined, Icons.event_available, _everyone),
  NavDestination('/staff', 'Staff', Icons.groups_outlined, Icons.groups, _managers),
  NavDestination('/geofence', 'Work sites', Icons.share_location_outlined, Icons.share_location, _managers),
  NavDestination('/reports', 'Reports', Icons.insert_chart_outlined, Icons.insert_chart, _managers),
  NavDestination('/settings', 'Settings', Icons.settings_outlined, Icons.settings, _everyone),
];

/// Returns true when [user] may open [path]. Used by the router guard.
bool canAccessPath(Employee user, String path) {
  if (path.startsWith('/admin')) return _systemAdmins(user);
  for (final d in appDestinations) {
    if (path.startsWith(d.path)) return d.visibleTo(user);
  }
  return true;
}

final _shellScaffoldKey = GlobalKey<ScaffoldState>();

/// Menu button for page app bars: opens the navigation drawer on narrow
/// layouts and is absent on wide layouts where the sidebar is always visible.
class ShellMenuButton extends StatelessWidget {
  const ShellMenuButton._();

  static Widget? maybe(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= AppShell.wideBreakpoint ? null : const ShellMenuButton._();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.menu),
      tooltip: 'Menu',
      onPressed: () => _shellScaffoldKey.currentState?.openDrawer(),
    );
  }
}

/// Persistent, responsive navigation frame for every signed-in page.
class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const wideBreakpoint = 1024.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final location = GoRouterState.of(context).uri.path;
    final destinations = appDestinations.where((d) => d.visibleTo(user)).toList();
    final isWide = MediaQuery.sizeOf(context).width >= wideBreakpoint;

    final sidebar = _Sidebar(user: user, destinations: destinations, location: location);

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 256, child: sidebar),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      key: _shellScaffoldKey,
      drawer: Drawer(width: 280, child: SafeArea(child: sidebar)),
      body: child,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  final Employee user;
  final List<NavDestination> destinations;
  final String location;

  const _Sidebar({required this.user, required this.destinations, required this.location});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    void go(String path) {
      _shellScaffoldKey.currentState?.closeDrawer();
      context.go(path);
    }

    return Container(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
            child: Row(
              children: [
                const BrandMark(size: 32),
                const SizedBox(width: 12),
                Text('Vigil', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final d in destinations)
                  _NavTile(
                    destination: d,
                    selected: location.startsWith(d.path),
                    onTap: () => go(d.path),
                  ),
                if (user.isSystemAdmin) ...[
                  const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16), child: Divider()),
                  _NavTile(
                    destination: const NavDestination('/admin', 'System Admin', Icons.admin_panel_settings_outlined,
                        Icons.admin_panel_settings, _systemAdmins),
                    selected: location.startsWith('/admin'),
                    onTap: () => go('/admin'),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _UserMenu(user: user),
          ),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  const _NavTile({required this.destination, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(selected ? destination.selectedIcon : destination.icon, size: 22, color: fg),
                const SizedBox(width: 14),
                Text(
                  destination.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: selected ? scheme.onSecondaryContainer : scheme.onSurface,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  final Employee user;
  const _UserMenu({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentTheme = ref.watch(themeProvider).currentTheme;

    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, -8),
      position: PopupMenuPosition.over,
      onSelected: (value) async {
        if (value == 'logout') {
          await ref.read(authProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        } else if (value == 'settings') {
          context.go('/settings');
        } else if (value == 'theme') {
          ref.read(themeProvider.notifier).toggle();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Text(user.email, style: theme.textTheme.bodySmall),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'theme',
          child: ListTile(
            dense: true,
            leading: Icon(currentTheme == AppTheme.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            title: Text(currentTheme == AppTheme.dark ? 'Switch to light mode' : 'Switch to dark mode'),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'settings', child: ListTile(dense: true, leading: Icon(Icons.person_outline), title: Text('Profile & settings'))),
        PopupMenuItem(
          value: 'logout',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out', style: TextStyle(color: theme.colorScheme.error)),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          children: [
            UserAvatar(name: user.fullName, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge),
                  Text(roleLabel(user.role), style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            Icon(Icons.unfold_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

String roleLabel(String role) => switch (role) {
      'system_admin' => 'System Admin',
      'owner' => 'Owner',
      'admin' => 'Admin',
      'hr' => 'HR',
      'manager' => 'Manager',
      _ => 'Staff',
    };

class UserAvatar extends StatelessWidget {
  final String name;
  final double radius;
  const UserAvatar({super.key, required this.name, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    // Stable per-person colour, like Google account avatars.
    const palette = [
      Color(0xFF1A73E8), Color(0xFFD93025), Color(0xFF188038), Color(0xFFE37400),
      Color(0xFF9334E6), Color(0xFF007B83), Color(0xFFC5221F), Color(0xFF1967D2),
    ];
    final color = palette[name.codeUnits.fold<int>(0, (a, c) => a + c) % palette.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.brightness == Brightness.dark ? color.withValues(alpha: 0.85) : color,
      child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: radius * 0.75)),
    );
  }
}

/// The Vigil logo mark, shared by the shell and the public pages.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        color: const Color(0xFF1A73E8),
      ),
      child: Icon(Icons.shield_outlined, size: size * 0.6, color: Colors.white),
    );
  }
}

/// Standard page header used at the top of every signed-in page.
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(subtitle!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 640 || actions.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleBlock,
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 16),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      );
    });
  }
}
