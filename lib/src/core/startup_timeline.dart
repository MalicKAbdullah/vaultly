import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Milestones from process start to the first vault frame, logged as
/// `vaultly.startup` in debug and profile builds. Read them with
/// `flutter run --profile` to see where an open spends its time.
abstract final class StartupTimeline {
  static final Stopwatch _clock = Stopwatch();
  static final Set<String> _once = {};

  static void start() => _clock.start();

  /// Logs [event] with the time since [start].
  static void mark(String event) {
    if (kReleaseMode) return;
    developer.log(
      '$event ${_clock.elapsedMilliseconds} ms',
      name: 'vaultly.startup',
    );
  }

  /// [mark], but only the first time [event] happens in this process.
  static void markOnce(String event) {
    if (_once.add(event)) mark(event);
  }

  /// [markOnce] once the frame being built now has been drawn.
  static void markOnceAfterFrame(String event) {
    if (kReleaseMode || !_once.add(event)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => mark(event));
  }
}
