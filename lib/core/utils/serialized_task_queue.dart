import 'dart:async';

/// Runs asynchronous tasks strictly in submission order.
///
/// Errors are delivered to the matching caller but are consumed by the queue,
/// so one native/media/file-system failure cannot poison every later action.
class SerializedTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}
