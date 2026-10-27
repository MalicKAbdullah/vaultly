import 'dart:async';
import 'dart:isolate';

/// Runs CPU-bound work over the whole vault (decrypt and parse, health
/// analysis) away from the UI isolate, so a large vault never drops frames.
abstract interface class IBackgroundWorker {
  Future<R> run<R>(FutureOr<R> Function() task);
}

/// A short-lived isolate per task. The task and its result are copied
/// between isolates, so callers send only plain data.
final class IsolateWorker implements IBackgroundWorker {
  const IsolateWorker();

  @override
  Future<R> run<R>(FutureOr<R> Function() task) => Isolate.run(task);
}
