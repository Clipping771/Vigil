import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'screens/login_screen.dart';
import 'screens/registration_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/staff_directory_screen.dart';
import 'screens/rosters_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/leave_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/landing_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/geofence_screen.dart';
import 'screens/splash_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'widgets/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isValid) {
    runApp(const _MisconfiguredApp());
    return;
  }

  await Supabase.initialize(url: Env.supabaseUrl, publishableKey: Env.supabaseAnonKey);

  runApp(const ProviderScope(child: VigilApp()));
}

const _publicPaths = {'/', '/login', '/register'};

/// Bridges Riverpod auth state into a [Listenable] so GoRouter re-runs its
/// redirect whenever the user signs in or out.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Ref ref) {
    ref.listen(authProvider, (_, _) => notifyListeners());
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRefresh(ref);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final path = state.uri.path;
      final isPublic = _publicPaths.contains(path);

      if (!auth.initialized) {
        return path == '/splash' ? null : '/splash?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      final user = auth.currentUser;
      if (path == '/splash') {
        final from = state.uri.queryParameters['from'];
        if (user == null) return (from != null && _publicPaths.contains(Uri.parse(from).path)) ? from : '/';
        return (from != null && !_publicPaths.contains(Uri.parse(from).path)) ? from : '/dashboard';
      }

      if (user == null) {
        return isPublic ? null : '/login?from=${Uri.encodeComponent(state.uri.toString())}';
      }

      if (path == '/login' || path == '/register') {
        final from = state.uri.queryParameters['from'];
        return from != null && !_publicPaths.contains(Uri.parse(from).path) ? from : '/dashboard';
      }

      if (!canAccessPath(user, path)) return '/dashboard';
      return null;
    },
    errorBuilder: (context, state) => const _NotFoundScreen(),
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
      GoRoute(path: '/', builder: (context, state) => const LandingScreen()),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegistrationScreen()),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/dashboard', pageBuilder: _fade(const DashboardScreen())),
          GoRoute(path: '/staff', pageBuilder: _fade(const StaffDirectoryScreen())),
          GoRoute(path: '/rosters', pageBuilder: _fade(const RostersScreen())),
          GoRoute(path: '/reports', pageBuilder: _fade(const ReportsScreen())),
          GoRoute(path: '/leave', pageBuilder: _fade(const LeaveScreen())),
          GoRoute(path: '/settings', pageBuilder: _fade(const SettingsScreen())),
          GoRoute(path: '/geofence', pageBuilder: _fade(const GeofenceScreen())),
          GoRoute(path: '/admin', pageBuilder: _fade(const AdminDashboardScreen())),
        ],
      ),
    ],
  );
});

Page<void> Function(BuildContext, GoRouterState) _fade(Widget child) {
  return (context, state) => CustomTransitionPage<void>(
        key: state.pageKey,
        child: child,
        transitionDuration: const Duration(milliseconds: 180),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(opacity: animation, child: child),
      );
}

class VigilApp extends ConsumerWidget {
  const VigilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeState = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Vigil — Workforce Compliance',
      debugShowCheckedModeBanner: false,
      theme: themeState.themeData,
      routerConfig: router,
    );
  }
}

class _NotFoundScreen extends StatelessWidget {
  const _NotFoundScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_off_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('Page not found', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('The page you are looking for does not exist.', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => context.go('/'), child: const Text('Go home')),
          ],
        ),
      ),
    );
  }
}

class _MisconfiguredApp extends StatelessWidget {
  const _MisconfiguredApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppTheme.dark),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_suggest_outlined, size: 48),
                const SizedBox(height: 16),
                const Text('Vigil is not configured', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  kReleaseMode
                      ? 'This deployment is missing its Supabase configuration. Please contact the administrator.'
                      : 'Run with --dart-define-from-file=.env (see .env.example) so SUPABASE_URL and SUPABASE_ANON_KEY are set.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
