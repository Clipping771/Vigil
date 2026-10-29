import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';

class AuthState {
  final Employee? currentUser;
  final bool isLoading;

  /// False until the persisted session (if any) has been restored on startup.
  final bool initialized;
  final String? error;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.initialized = false,
    this.error,
  });

  bool get isAuthenticated => currentUser != null;
}

/// Result of a sign-up attempt.
enum SignUpOutcome { signedIn, confirmationRequired }

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  final _supabase = Supabase.instance.client;
  StreamSubscription<dynamic>? _authSub;

  Future<void> _init() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _bootstrap();
    } else {
      state = const AuthState(initialized: true);
    }

    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedOut) {
        state = const AuthState(initialized: true);
      }
    });
  }

  /// Resolves (and on first sign-in, links or creates) the employee profile for
  /// the authenticated Supabase user via the `link_current_user` RPC.
  Future<void> _bootstrap() async {
    try {
      final response = await _supabase.rpc('link_current_user');
      final row = response is List ? response.first : response;
      state = AuthState(initialized: true, currentUser: Employee.fromJson(Map<String, dynamic>.from(row)));
    } on PostgrestException catch (e) {
      await _supabase.auth.signOut();
      state = AuthState(initialized: true, error: e.message);
    } catch (e) {
      debugPrint('Profile bootstrap failed: $e');
      await _supabase.auth.signOut();
      state = const AuthState(initialized: true, error: 'Could not load your profile. Please try again.');
    }
  }

  Future<void> login(String email, String password) async {
    state = const AuthState(isLoading: true, initialized: true);
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      await _bootstrap();
    } on AuthException catch (e) {
      state = AuthState(initialized: true, error: _friendlyAuthError(e));
    } catch (e) {
      state = const AuthState(initialized: true, error: 'Unable to reach the server. Check your connection.');
    }
  }

  /// Creates a Supabase Auth account. When [companyName] is provided, a new
  /// organization is created on first sign-in with this user as owner; otherwise
  /// the account links to an employee record an administrator has provisioned.
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    String? fullName,
    String? companyName,
  }) async {
    state = const AuthState(isLoading: true, initialized: true);
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: kIsWeb ? Uri.base.origin : null,
        data: {
          if (fullName != null && fullName.isNotEmpty) 'full_name': fullName,
          if (companyName != null && companyName.isNotEmpty) 'company_name': companyName,
        },
      );
      if (response.session == null) {
        state = const AuthState(initialized: true);
        return SignUpOutcome.confirmationRequired;
      }
      await _bootstrap();
      if (state.error != null) throw AuthException(state.error!);
      return SignUpOutcome.signedIn;
    } on AuthException catch (e) {
      state = AuthState(initialized: true, error: _friendlyAuthError(e));
      rethrow;
    }
  }

  Future<void> sendPasswordReset(String email) async {
    await _supabase.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? Uri.base.origin : null,
    );
  }

  /// Re-fetches the current profile (e.g. after editing own details).
  Future<void> refreshProfile() async {
    if (_supabase.auth.currentSession != null) await _bootstrap();
  }

  void clearError() {
    if (state.error != null) {
      state = AuthState(initialized: state.initialized, currentUser: state.currentUser);
    }
  }

  Future<void> logout() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Sign-out error: $e');
    }
    state = const AuthState(initialized: true);
  }

  String _friendlyAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) return 'Incorrect email or password.';
    if (msg.contains('email not confirmed')) return 'Please confirm your email address, then sign in.';
    if (msg.contains('already registered')) return 'An account with this email already exists. Sign in instead.';
    if (msg.contains('rate limit')) return 'Too many attempts. Please wait a minute and try again.';
    return e.message;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

/// Role helpers shared by navigation, route guards and screens.
extension EmployeeRoles on Employee {
  bool get isSystemAdmin => role == 'system_admin';
  bool get isOrgAdmin => const {'owner', 'admin', 'system_admin'}.contains(role);
  bool get isManager => const {'owner', 'admin', 'system_admin', 'manager', 'hr'}.contains(role);
}
