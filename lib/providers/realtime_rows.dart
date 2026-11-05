import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

/// Calls [reload] once when rows on the list are deleted. A cascade deletes many
/// rows in a burst, so the deletes are gathered first. Delete events are not
/// limited to this organization, so ids that are not listed are ignored.
class DeletedRowWatcher {
  final void Function() reload;
  final Duration delay;
  Set<Object?> _listed = const {};
  Timer? _timer;

  DeletedRowWatcher(this.reload, {this.delay = const Duration(milliseconds: 400)});

  void track(Iterable<Map<String, dynamic>> rows) => _listed = {for (final r in rows) r['id']};

  void onDeleted(Map<String, dynamic> oldRecord) {
    if (!_listed.contains(oldRecord['id'])) return;
    _timer?.cancel();
    _timer = Timer(delay, reload);
  }

  void dispose() => _timer?.cancel();
}

/// Listens for deletes on [table] with no filter. A subscription filtered by
/// organization only receives deletes if the table has REPLICA IDENTITY FULL, so
/// relying on it can leave deleted rows on screen until the page is reloaded.
RealtimeChannel listenForDeletes(String table, void Function(Map<String, dynamic> oldRecord) onDeleted) {
  return Supabase.instance.client
      .channel('deletes_${table}_${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: table,
        callback: (payload) => onDeleted(payload.oldRecord),
      )
      .subscribe();
}

/// Cleans batches from a `.stream()` of [table] filtered by organization, and
/// reloads the provider when one of its rows is deleted.
List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) liveRows(Ref ref, String table) {
  final watcher = DeletedRowWatcher(ref.invalidateSelf);
  final channel = listenForDeletes(table, watcher.onDeleted);
  ref.onDispose(() {
    watcher.dispose();
    Supabase.instance.client.removeChannel(channel);
  });
  return (rows) {
    final unique = withoutDuplicateRows(ref, rows);
    watcher.track(unique);
    return unique;
  };
}
