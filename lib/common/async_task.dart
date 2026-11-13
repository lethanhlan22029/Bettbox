import 'dart:async';

/// Schedules independent work without inheriting a caller's reentrant lock.
/// Deliver failures through the caller's zone so guarded error handlers remain
/// effective even though the work itself starts in the root zone.
Future<T> runDetached<T>(FutureOr<T> Function() task) {
  final result = Completer<T>();
  Zone.root.run(() {
    Future<T>.microtask(
      task,
    ).then(result.complete, onError: result.completeError);
  });
  return result.future;
}
