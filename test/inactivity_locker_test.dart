import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/core/security/inactivity_locker.dart';
import 'package:vaultkey/src/features/auth/providers/auth_providers.dart';

import 'fakes/fakes.dart';

void main() {
  testWidgets('idle time ends the fill session; leaving the app does not', (
    tester,
  ) async {
    final bridge = FakeFillSessionBridge();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        fileStoreProvider.overrideWithValue(InMemoryFileStore()),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
        fillSessionBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      container.listen(sessionProvider, (_, __) {});
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(sessionProvider.notifier).setup('a long password');
    });
    expect(container.read(sessionProvider), AuthStatus.unlocked);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: InactivityLocker(child: SizedBox.expand()),
        ),
      ),
    );
    // A pointer event arms the inactivity timer.
    await tester.tapAt(const Offset(10, 10));

    await tester.pump(const Duration(minutes: 1));
    expect(bridge.clears, 0);
    await tester.pump(const Duration(minutes: 1, seconds: 1));
    expect(bridge.clears, 1);
  });

  testWidgets('leaving the app locks without ending the session', (
    tester,
  ) async {
    final bridge = FakeFillSessionBridge();
    final container = ProviderContainer(
      overrides: [
        secureStorageProvider.overrideWithValue(FakeSecureStorage()),
        fileStoreProvider.overrideWithValue(InMemoryFileStore()),
        keyDerivationProvider.overrideWithValue(FakeKeyDerivation()),
        backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
        fillSessionBridgeProvider.overrideWithValue(bridge),
      ],
    );
    addTearDown(container.dispose);
    await tester.runAsync(() async {
      container.listen(sessionProvider, (_, __) {});
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      await container.read(sessionProvider.notifier).setup('a long password');
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: InactivityLocker(child: SizedBox.expand()),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(container.read(sessionProvider), AuthStatus.locked);
    expect(bridge.clears, 0);
  });
}
