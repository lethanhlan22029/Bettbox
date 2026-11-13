import 'dart:async';

import 'package:bett_box/common/async_task.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synchronized/synchronized.dart';

void main() {
  test(
    'independent work queues behind the active lifecycle operation',
    () async {
      final lock = Lock(reentrant: true);
      final queued = Completer<void>();
      final finish = Completer<void>();
      final events = <String>[];
      late Future<void> background;
      final parent = lock.synchronized(() async {
        events.add('parent start');
        background = runDetached(() {
          queued.complete();
          return lock.synchronized(() async {
            events.add('background');
          });
        });
        await finish.future;
        events.add('parent end');
      });
      await queued.future;
      expect(events, ['parent start']);
      finish.complete();
      await parent;
      await background;
      expect(events, ['parent start', 'parent end', 'background']);
    },
  );

  test(
    'late work can acquire the lock after nested parents complete',
    () async {
      final lock = Lock(reentrant: true);
      final resume = Completer<void>();
      late Future<int> background;
      await lock.synchronized(() async {
        await lock.synchronized(() async {
          background = runDetached(() async {
            await resume.future;
            return lock.synchronized(() => 42);
          });
        });
      });
      resume.complete();
      expect(await background, 42);
      expect(await lock.synchronized(() => 43), 43);
    },
  );

  test('failures are returned to the caller across guarded zones', () async {
    final caught = Completer<Object>();
    final escaped = <Object>[];
    runZonedGuarded(() async {
      try {
        await runDetached<void>(() => throw StateError('background failed'));
      } catch (error) {
        caught.complete(error);
      }
    }, (error, _) => escaped.add(error));
    expect(await caught.future, isA<StateError>());
    expect(escaped, isEmpty);
  });
}
