import 'dart:async';
import 'dart:typed_data';

/// Thrown when the other device breaks the protocol, fails authentication,
/// or goes away. [message] is safe to show.
final class SyncProtocolException implements Exception {
  const SyncProtocolException(this.message);

  final String message;

  @override
  String toString() => 'SyncProtocolException: $message';
}

/// Length-prefixed frames over a byte stream (a TCP socket, or an in-memory
/// pipe in tests): a 4-byte big-endian length, then the payload.
final class FrameChannel {
  FrameChannel({
    required Stream<List<int>> input,
    required void Function(List<int> bytes) output,
    required Future<void> Function() close,
  })  : _output = output,
        _close = close {
    _subscription = input.listen(
      _onData,
      onError: (Object _) => _fail('The connection dropped.'),
      onDone: () => _fail('The other device disconnected.'),
      cancelOnError: true,
    );
  }

  /// Larger frames are refused before any allocation, so a peer cannot make
  /// this device reserve unbounded memory.
  static const int maxFrameBytes = 64 * 1024 * 1024;

  final void Function(List<int> bytes) _output;
  final Future<void> Function() _close;
  late final StreamSubscription<List<int>> _subscription;

  final _buffer = BytesBuilder(copy: false);

  /// Payload length of the frame being received, once its header is in.
  int? _need;
  final _frames = <Uint8List>[];
  Completer<Uint8List>? _waiting;
  SyncProtocolException? _error;

  void send(List<int> payload) {
    final frame = Uint8List(4 + payload.length);
    ByteData.sublistView(frame).setUint32(0, payload.length);
    frame.setRange(4, frame.length, payload);
    _output(frame);
  }

  /// The next frame. Throws [SyncProtocolException] once the stream ends
  /// or misbehaves, or when no frame arrives within [timeout].
  Future<Uint8List> receive({
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (_frames.isNotEmpty) return Future.value(_frames.removeAt(0));
    if (_error != null) return Future.error(_error!);
    final completer = _waiting = Completer<Uint8List>();
    return completer.future.timeout(timeout, onTimeout: () {
      _waiting = null;
      throw const SyncProtocolException('The other device stopped responding.');
    });
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _close();
  }

  void _onData(List<int> chunk) {
    _buffer.add(chunk);
    while (true) {
      var need = _need;
      if (need == null) {
        if (_buffer.length < 4) return;
        final bytes = _buffer.takeBytes();
        need = ByteData.sublistView(bytes, 0, 4).getUint32(0);
        if (need > maxFrameBytes) {
          _fail('The other device sent too much data.');
          unawaited(_subscription.cancel());
          return;
        }
        _need = need;
        _buffer.add(Uint8List.sublistView(bytes, 4));
      }
      if (_buffer.length < need) return;
      final bytes = _buffer.takeBytes();
      _need = null;
      if (bytes.length > need) _buffer.add(Uint8List.sublistView(bytes, need));
      _deliver(Uint8List.fromList(Uint8List.sublistView(bytes, 0, need)));
    }
  }

  void _deliver(Uint8List frame) {
    final waiting = _waiting;
    if (waiting != null) {
      _waiting = null;
      waiting.complete(frame);
    } else {
      _frames.add(frame);
    }
  }

  void _fail(String message) {
    _error ??= SyncProtocolException(message);
    final waiting = _waiting;
    _waiting = null;
    waiting?.completeError(_error!);
  }
}
