import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/exception_record.dart';

// Provides a real-time stream of all exception records from Supabase
final exceptionStreamProvider = StreamProvider<List<ExceptionRecord>>((ref) {
  return Supabase.instance.client
      .from('exception_records')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false)
      .map((data) => data.map((json) => ExceptionRecord.fromJson(json)).toList());
});

// Derived provider for only active (pending or acknowledged) exceptions
final activeExceptionsProvider = Provider<AsyncValue<List<ExceptionRecord>>>((ref) {
  final exceptionsAsync = ref.watch(exceptionStreamProvider);
  
  return exceptionsAsync.whenData((exceptions) {
    return exceptions.where((ex) => ex.status != 'resolved').toList();
  });
});

class ExceptionService {
  final _supabase = Supabase.instance.client;

  Future<void> resolveException(String id) async {
    await _supabase
        .from('exception_records')
        .update({'status': 'resolved', 'resolved_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  Future<void> acknowledgeException(String id) async {
    await _supabase
        .from('exception_records')
        .update({'status': 'acknowledged'})
        .eq('id', id);
  }
}

final exceptionServiceProvider = Provider<ExceptionService>((ref) {
  return ExceptionService();
});
