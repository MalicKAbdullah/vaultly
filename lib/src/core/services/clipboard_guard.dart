import 'dart:async';

import 'package:flutter/services.dart';

/// Abstraction over the system clipboard so the auto-clear logic can be
/// tested without platform channels.
abstract interface class ISystemClipboard {
  Future<void> setText(String text);

  Future<String?> getText();
}

final class FlutterSystemClipboard implements ISystemClipboard {
  const FlutterSystemClipboard();

  @override
  Future<void> setText(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> getText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}

/// Copies values to the clipboard; sensitive copies are automatically
/// cleared after [clearAfter] — but only when the clipboard still holds the
/// copied value, so a newer copy from another app is never destroyed.
final class ClipboardGuard {
  ClipboardGuard({
    required ISystemClipboard clipboard,
    this.clearAfter = const Duration(seconds: 30),
  }) : _clipboard = clipboard;

  final ISystemClipboard _clipboard;
  final Duration clearAfter;

  Timer? _timer;
  String? _pending;

  /// Copies a non-sensitive value; no auto-clear is scheduled.
  Future<void> copy(String value) => _clipboard.setText(value);

  /// Copies a sensitive value and schedules the auto-clear.
  Future<void> copySensitive(String value) async {
    await _clipboard.setText(value);
    _pending = value;
    _timer?.cancel();
    _timer = Timer(clearAfter, () => unawaited(clearIfUnchanged()));
  }

  /// Clears the clipboard if it still holds the last sensitive copy.
  Future<void> clearIfUnchanged() async {
    final pending = _pending;
    _pending = null;
    _timer?.cancel();
    _timer = null;
    if (pending == null) return;
    final current = await _clipboard.getText();
    if (current == pending) {
      await _clipboard.setText('');
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
