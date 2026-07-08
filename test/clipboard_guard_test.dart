import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/services/clipboard_guard.dart';

import 'fakes/fakes.dart';

void main() {
  group('ClipboardGuard', () {
    test('sensitive copy clears the clipboard after the TTL', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(clipboard: clipboard);

        guard.copySensitive('secret-value');
        async.flushMicrotasks();
        expect(clipboard.text, 'secret-value');

        async.elapse(const Duration(seconds: 29));
        expect(clipboard.text, 'secret-value');

        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(clipboard.text, '');
      });
    });

    test('does not clear when the clipboard changed in the meantime', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(clipboard: clipboard);

        guard.copySensitive('secret-value');
        async.flushMicrotasks();
        clipboard.text = 'something the user copied elsewhere';

        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
        expect(clipboard.text, 'something the user copied elsewhere');
      });
    });

    test('a second sensitive copy restarts the timer', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(clipboard: clipboard);

        guard.copySensitive('first');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));

        guard.copySensitive('second');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 20));
        // 40s after the first copy, but only 20s after the second.
        expect(clipboard.text, 'second');

        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(clipboard.text, '');
      });
    });

    test('plain copy never schedules a clear', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(clipboard: clipboard);

        guard.copy('public value');
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 5));
        async.flushMicrotasks();
        expect(clipboard.text, 'public value');
      });
    });

    test('clearIfUnchanged on lock clears an armed copy immediately', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(clipboard: clipboard);

        guard.copySensitive('secret-value');
        async.flushMicrotasks();
        guard.clearIfUnchanged();
        async.flushMicrotasks();
        expect(clipboard.text, '');
      });
    });

    test('custom TTL is honored', () {
      fakeAsync((async) {
        final clipboard = FakeClipboard();
        final guard = ClipboardGuard(
          clipboard: clipboard,
          clearAfter: const Duration(seconds: 5),
        );
        guard.copySensitive('secret');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        expect(clipboard.text, '');
      });
    });
  });
}
