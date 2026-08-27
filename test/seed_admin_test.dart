import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() {
  test('Seed Admin User', () async {
    // We don't need UI, just the Supabase client
    await dotenv.load(fileName: ".env");
    
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final supabaseKey = dotenv.env['SUPABASE_ANON_KEY']!;
    
    final supabase = SupabaseClient(
      supabaseUrl, 
      supabaseKey,
      authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit),
    );

    try {
      final res = await supabase.from('employees').select('email, role, id');
      print('EMPLOYEES IN DB:');
      print(res);
    } catch (e) {
      print('FAILED: $e');
    }
  });
}
