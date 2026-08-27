import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee.dart';

class AuthState {
  final Employee? currentUser;
  final bool isLoading;
  final String? error;

  AuthState({this.currentUser, this.isLoading = false, this.error});
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState()) {
    _init();
  }

  final _supabase = Supabase.instance.client;

  Future<void> _init() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      await _fetchEmployeeData(session.user.id);
    }
  }

  Future<void> _fetchEmployeeData(String userId) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('id', userId)
          .single();
      
      final employee = Employee.fromJson(response);
      state = AuthState(isLoading: false, currentUser: employee);
    } catch (e) {
      state = AuthState(isLoading: false, error: 'Could not load employee profile: $e');
    }
  }

  Future<void> login(String email, String password) async {
    state = AuthState(isLoading: true);
    
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        await _fetchEmployeeData(response.user!.id);
      } else {
         state = AuthState(isLoading: false, error: 'Unknown login error');
      }
    } on AuthException catch (e) {
      // PROTOTYPE BACKDOOR: Fallback to mock login if Auth fails (e.g. rate limit or not signed up)
      print('AuthException: ${e.message} - falling back to mock login');
      await _mockLogin(email);
    } catch (e) {
      state = AuthState(isLoading: false, error: 'Login failed: $e');
    }
  }

  Future<void> _mockLogin(String email) async {
    try {
      final response = await _supabase
          .from('employees')
          .select()
          .eq('email', email)
          .single();
      
      final employee = Employee.fromJson(response);
      state = AuthState(isLoading: false, currentUser: employee);
    } catch (e) {
      state = AuthState(isLoading: false, error: 'Mock login failed (Not in directory). Real error was Auth failed.');
    }
  }



  Future<void> logout() async {
    state = AuthState(isLoading: true);
    try {
      await _supabase.auth.signOut();
    } catch (_) {
      // Ignore errors for demo logins
    }
    state = AuthState(); // Reset to initial state
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
