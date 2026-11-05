import 'package:flutter_riverpod/flutter_riverpod.dart';

/// [rows] with one row per `id`, keeping the first of each and the order.
List<Map<String, dynamic>> uniqueRowsById(List<Map<String, dynamic>> rows) {
  final byId = <Object?, Map<String, dynamic>>{};
  for (final row in rows) {
    byId.putIfAbsent(row['id'], () => row);
  }
  return byId.values.toList();
}

/// Cleans a batch from a Supabase `.stream()`, which appends each realtime insert
/// without checking its id. An insert that arrives just after the first load
/// therefore lists that row twice. The stream's own copy stays wrong, and later
/// updates and deletes only reach one of the two, so reload to replace it.
List<Map<String, dynamic>> withoutDuplicateRows(Ref ref, List<Map<String, dynamic>> rows) {
  final unique = uniqueRowsById(rows);
  if (unique.length != rows.length) ref.invalidateSelf();
  return unique;
}
