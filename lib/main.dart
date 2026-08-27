import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables for Flutter app
  await dotenv.load(fileName: ".env");

  // Initialize Supabase Client using environment variables
  final supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
  } else {
    print('ERROR: Missing Supabase credentials in .env file');
  }

  // MockDatabase is deprecated in favor of real Supabase connection
  // Initialize local persistence for the prototype (removed)

  runApp(const ProviderScope(child: VigilApp()));
}

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const LandingScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegistrationScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => const DashboardScreen(),
      ),
      GoRoute(
        path: '/staff',
        builder: (context, state) => const StaffDirectoryScreen(),
      ),
      GoRoute(
        path: '/rosters',
        builder: (context, state) => const RostersScreen(),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => const ReportsScreen(),
      ),
      GoRoute(
        path: '/leave',
        builder: (context, state) => const LeaveScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminDashboardScreen(),
      ),
    ],
  );
});

class VigilApp extends ConsumerWidget {
  const VigilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);

    // Watch the theme state
    final themeState = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'Vigil',
      debugShowCheckedModeBanner: false,
      theme: themeState.themeData,
      routerConfig: router,
    );
  }
}
