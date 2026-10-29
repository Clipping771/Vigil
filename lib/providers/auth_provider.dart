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

  /// True after opening a password-reset email link: the user must choose a
  /// new password before continuing.
  final bool passwordRecovery;

  const AuthState({
    this.currentUser,
    this.isLoading = false,
    this.initialized = false,
    this.error,
    this.passwordRecovery = false,
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
    // Listen first so sessions created from an email link (sign-up
    // confirmation, invite, password reset) are picked up.
    _authSub = _supabase.auth.onAuthStateChange.listen((data) async {
      switch (data.event) {
        case AuthChangeEvent.signedOut:
          state = const AuthState(initialized: true);
        case AuthChangeEvent.passwordRecovery:
          await _bootstrap(passwordRecovery: true);
        case AuthChangeEvent.signedIn:
          // login()/signUp() bootstrap themselves; this covers email links.
          if (!state.isLoading && state.currentUser == null) await _bootstrap();
        default:
          break;
      }
    });

    final session = _supabase.auth.currentSession;
    if (session != null) {
      if (state.currentUser == null) await _bootstrap();
    } else {
      state = AuthState(initialized: true, error: _linkErrorFromUrl());
    }
  }

  /// Supabase appends `error_description` to the redirect URL when an email
  /// link is expired or was already used.
  String? _linkErrorFromUrl() {
    if (!kIsWeb) return null;
    final params = {...Uri.base.queryParameters, ...Uri.splitQueryString(Uri.base.fragment.contains('=') ? Uri.base.fragment.split('?').last : '')};
    final code = params['error_code'];
    if (code == null && params['error'] == null) return null;
    if (code == 'otp_expired') {
      return 'That email link has expired or was already used. Sign in, or request a new link below.';
    }
    return params['error_description']?.replaceAll('+', ' ') ?? 'That email link is no longer valid.';
  }

  /// Resolves (and on first sign-in, links or creates) the employee profile for
  /// the authenticated Supabase user via the `link_current_user` RPC.
  Future<void> _bootstrap({bool passwordRecovery = false}) async {
    try {
      final response = await _supabase.rpc('link_current_user');
      final row = response is List ? response.first : response;
      state = AuthState(
        initialized: true,
        currentUser: Employee.fromJson(Map<String, dynamic>.from(row)),
        passwordRecovery: passwordRecovery || state.passwordRecovery,
      );
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

  /// Sets a new password for the signed-in user (after a reset link).
  Future<void> updatePassword(String newPassword) async {
    await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    state = AuthState(initialized: true, currentUser: state.currentUser);
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
      state = AuthState(initialized: state.initialized, currentUser: state.currentUser, passwordRecovery: state.passwordRecovery);
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
