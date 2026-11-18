import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/health/screens/health_screen.dart';
import 'package:vaultkey/src/features/health/services/fix_it.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('Change password arms the entry and opens the well-known page', (
    tester,
  ) async {
    final launched = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        launched.add(call);
        return true;
      },
    );
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bridge = FakeFillSessionBridge();
    final entry = makeEntry(
      id: 'weak',
      title: 'Weak site',
      password: 'abc',
      url: 'weak.example',
    );
    final container = ProviderContainer(
      overrides: [
        vaultEntriesProvider.overrideWith(() => FakeVaultNotifier([entry])),
        clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
        fillSessionBridgeProvider.overrideWithValue(bridge),
        backgroundWorkerProvider.overrideWithValue(const InlineWorker()),
      ],
    );
    addTearDown(container.dispose);
    container.listen(vaultHealthProvider, (_, __) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HealthScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('Change password').first);
    await tester.pump();
    await tester.pump();

    expect(bridge.armedEntryId, 'weak');
    expect(container.read(fixTargetProvider)?.entryId, 'weak');
    expect(container.read(fixTargetProvider)?.host, 'weak.example');
    expect(
      launched.single.arguments['url'],
      'https://weak.example/.well-known/change-password',
    );
  });
}
