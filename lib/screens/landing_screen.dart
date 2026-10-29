import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../widgets/app_shell.dart';

class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: _NavBar()),
          const SliverToBoxAdapter(child: _Hero()),
          const SliverToBoxAdapter(child: _Features()),
          const SliverToBoxAdapter(child: _HowItWorks()),
          const SliverToBoxAdapter(child: _CallToAction()),
          const SliverToBoxAdapter(child: _Footer()),
        ],
      ),
    );
  }
}

/// Centers page content at a readable max width with responsive gutters.
class _Section extends StatelessWidget {
  final Widget child;
  final double vertical;
  const _Section({required this.child, this.vertical = 72});

  @override
  Widget build(BuildContext context) {
    final gutter = MediaQuery.sizeOf(context).width < 600 ? 20.0 : 40.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1160),
        child: Padding(padding: EdgeInsets.symmetric(horizontal: gutter, vertical: vertical), child: child),
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar();

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return _Section(
      vertical: 20,
      child: Row(
        children: [
          const BrandMark(size: 32),
          const SizedBox(width: 10),
          const Text('Vigil', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton(onPressed: () => context.go('/login'), child: const Text('Sign in')),
          if (!compact) ...[
            const SizedBox(width: 8),
            FilledButton(onPressed: () => context.go('/register'), child: const Text('Get started')),
          ],
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final headlineSize = width < 600 ? 36.0 : (width < 1000 ? 48.0 : 60.0);

    return _Section(
      vertical: width < 600 ? 40 : 88,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
            ),
            child: Text('Attendance · Rostering · Compliance',
                style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 28),
          Text(
            'Know who\'s on shift.\nCatch compliance issues early.',
            textAlign: TextAlign.center,
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: headlineSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              'Vigil gives frontline teams a geofenced punch clock and gives managers a live view of attendance, '
              'rosters, leave and Fair Work exceptions — all in one secure, multi-tenant workspace.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w400,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 36),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => context.go('/register'),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('Create your workspace'),
                style: FilledButton.styleFrom(minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 24)),
              ),
              OutlinedButton(
                onPressed: () => context.go('/login'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 24)),
                child: const Text('Sign in to your team'),
              ),
            ],
          ),
        ],
      ).animate().fadeIn(duration: 500.ms).slideY(begin: 0.06, end: 0),
    );
  }
}

class _Features extends StatelessWidget {
  const _Features();

  static const _items = [
    (Icons.share_location_outlined, 'Geofenced punch clock',
        'Staff clock in and out from their phone. GPS is checked against your work sites and out-of-zone punches are flagged.'),
    (Icons.monitor_heart_outlined, 'Live workforce board',
        'See who is on shift, on break or missing in real time, streamed straight from the database.'),
    (Icons.calendar_month_outlined, 'Rosters & scheduling',
        'Plan shifts on a calendar, spot leave conflicts, and give every employee a clear view of their week.'),
    (Icons.event_available_outlined, 'Leave management',
        'Request, approve and track annual, sick and personal leave with balances and roster-conflict checks.'),
    (Icons.policy_outlined, 'Compliance exceptions',
        'Late starts, overtime, missed breaks and geofence breaches become actionable items for managers to resolve.'),
    (Icons.lock_outline, 'Secure by default',
        'Every organization is isolated with row-level security. Roles control exactly who can see and change what.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      child: Column(
        children: [
          Text('Everything your shift-based team needs', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text('One platform from the punch clock to the payroll-ready report.',
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 48),
          LayoutBuilder(builder: (context, c) {
            final columns = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
            const gap = 20.0;
            final w = (c.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final (icon, title, body) in _items)
                  SizedBox(
                    width: w,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(icon, color: theme.colorScheme.primary, size: 22),
                            ),
                            const SizedBox(height: 18),
                            Text(title, style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(body, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const steps = [
      ('1', 'Create your workspace', 'Sign up and your organization is provisioned instantly with you as owner.'),
      ('2', 'Add sites and staff', 'Draw geofence zones, invite employees by email and assign roles.'),
      ('3', 'Run your shifts', 'Publish rosters, let staff punch in, and resolve exceptions as they appear.'),
    ];
    return Container(
      color: theme.colorScheme.surface,
      child: _Section(
        child: Column(
          children: [
            Text('Up and running in minutes', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
            const SizedBox(height: 40),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 40,
              runSpacing: 32,
              children: [
                for (final (n, title, body) in steps)
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: theme.colorScheme.primary,
                          child: Text(n, style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(height: 16),
                        Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(body,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.5)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallToAction extends StatelessWidget {
  const _CallToAction();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Section(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [theme.colorScheme.primary.withValues(alpha: 0.18), theme.colorScheme.secondary.withValues(alpha: 0.08)],
          ),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text('Ready to bring order to your shifts?', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => context.go('/register'), child: const Text('Get started free')),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.colorScheme.outline))),
      child: _Section(
        vertical: 28,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [BrandMark(size: 22), SizedBox(width: 8), Text('Vigil', style: TextStyle(fontWeight: FontWeight.w700))],
            ),
            Text('© ${DateTime.now().year} Vigil. All rights reserved.', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
