import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _companyController = TextEditingController();
  
  bool _isLoading = false;
  final _supabase = Supabase.instance.client;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    super.dispose();
  }

  void _completeSetup() async {
    final email = _emailController.text.trim();
    final name = _nameController.text.trim();
    final companyName = _companyController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;
    
    if (email.isEmpty || name.isEmpty || companyName.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all fields.'), backgroundColor: Colors.red),
      );
      return;
    }

    if (password != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final authResponse = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name},
      );

      if (authResponse.user != null) {
        // Generate new Organization ID using Postgres gen_random_uuid() or dart uuid
        final orgId = const Uuid().v4();

        // 1. Create the new Organization
        await _supabase.from('organizations').insert({
          'id': orgId,
          'name': companyName,
          'subscription_plan': 'enterprise' // default to enterprise trial
        });

        // 2. Insert into employees table as system_admin
        await _supabase.from('employees').insert({
          'id': authResponse.user!.id,
          'email': email,
          'full_name': name,
          'role': 'system_admin', // The creator of the org is the system_admin
          'organization_id': orgId
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created successfully! Please log in.'), backgroundColor: Colors.green),
          );
          context.go('/login');
        }
      }
    } on AuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: Colors.red));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Registration error: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
          onPressed: () => context.go('/login'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            width: 400,
            padding: const EdgeInsets.all(32.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.how_to_reg, size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Register a New Organization',
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a secure workspace for your company',
                  style: GoogleFonts.inter(color: Colors.grey[500], fontSize: 14),
                ),
                const SizedBox(height: 32),
                
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _companyController,
                  decoration: const InputDecoration(
                    labelText: 'Company Name',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Work Email Address',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm Password',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: const Color(0xFF10B981)), // Green for success
                    onPressed: _isLoading ? null : _completeSetup,
                    child: _isLoading 
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('New Organization? Setup Your Workspace', style: TextStyle(fontWeight: FontWeight.bold)),
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
