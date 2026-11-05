import 'package:flutter_test/flutter_test.dart';
import 'package:vigil/providers/realtime_rows.dart';

void main() {
  group('DeletedRowWatcher', () {
    const delay = Duration(milliseconds: 400);
    late int reloads;
    late DeletedRowWatcher watcher;

    void start() {
      reloads = 0;
      watcher = DeletedRowWatcher(() => reloads++, delay: delay);
      addTearDown(watcher.dispose);
      watcher.track([
        {'id': 'alice'},
        {'id': 'bob'},
      ]);
    }

    testWidgets('reloads when a listed row is deleted', (tester) async {
      start();
      watcher.onDeleted({'id': 'alice'});
      expect(reloads, 0);
      await tester.pump(delay);
      expect(reloads, 1);
    });

    testWidgets('a burst of deletes reloads once', (tester) async {
      start();
      watcher.onDeleted({'id': 'alice'});
      await tester.pump(const Duration(milliseconds: 100));
      watcher.onDeleted({'id': 'bob'});
      await tester.pump(delay);
      expect(reloads, 1);
    });

    testWidgets("ignores another organization's rows", (tester) async {
      start();
      watcher.onDeleted({'id': 'someone-else'});
      await tester.pump(delay);
      expect(reloads, 0);
    });

    testWidgets('follows the latest rows', (tester) async {
      start();
      watcher.track([
        {'id': 'carol'},
      ]);
      watcher.onDeleted({'id': 'alice'});
      await tester.pump(delay);
      expect(reloads, 0);
      watcher.onDeleted({'id': 'carol'});
      await tester.pump(delay);
      expect(reloads, 1);
    });

    testWidgets('does not reload after it is disposed', (tester) async {
      start();
      watcher.onDeleted({'id': 'alice'});
      watcher.dispose();
      await tester.pump(delay);
      expect(reloads, 0);
    });
  });
}
