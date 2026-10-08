import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/exception_record.dart';

class ExceptionNotifier extends StateNotifier<AsyncValue<List<ExceptionRecord>>> {
  final _supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;

  ExceptionNotifier() : super(const AsyncValue.loading()) {
    fetchExceptions();
    _setupRealtime();
  }

  void _setupRealtime() {
    _subscription = _supabase.channel('public_exception_records_feed')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'exception_records',
        callback: (_) {
          fetchExceptions();
        },
      )
      ..subscribe();
  }

  Future<void> fetchExceptions() async {
    try {
      final response = await _supabase
          .from('exception_records')
          .select()
          .order('created_at', ascending: false);

      final list = (response as List).map((json) => ExceptionRecord.fromJson(json)).toList();
      state = AsyncValue.data(list);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  @override
  void dispose() {
    _subscription?.unsubscribe();
    super.dispose();
  }
}

final exceptionStreamProvider = StateNotifierProvider<ExceptionNotifier, AsyncValue<List<ExceptionRecord>>>((ref) {
  return ExceptionNotifier();
});

// Derived provider for only active (pending or acknowledged) exceptions
final activeExceptionsProvider = Provider<AsyncValue<List<ExceptionRecord>>>((ref) {
  final exceptionsAsync = ref.watch(exceptionStreamProvider);

  return exceptionsAsync.whenData((exceptions) {
    return exceptions.where((ex) => ex.status != 'resolved').toList();
  });
});

class ExceptionService {
  final Ref _ref;
  final _supabase = Supabase.instance.client;

  ExceptionService(this._ref);

  Future<void> resolveException(String id) async {
    await _supabase
        .from('exception_records')
        .update({'status': 'resolved', 'resolved_at': DateTime.now().toIso8601String()})
        .eq('id', id);

    _ref.read(exceptionStreamProvider.notifier).fetchExceptions();
  }

  Future<void> acknowledgeException(String id) async {
    await _supabase
        .from('exception_records')
        .update({'status': 'acknowledged'})
        .eq('id', id);

    _ref.read(exceptionStreamProvider.notifier).fetchExceptions();
  }
}

final exceptionServiceProvider = Provider<ExceptionService>((ref) {
  return ExceptionService(ref);
});
