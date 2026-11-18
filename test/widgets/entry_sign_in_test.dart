import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/di.dart';
import 'package:vaultkey/src/features/totp/models/totp_config.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';
import 'package:vaultkey/src/features/vault/screens/entry_detail_screen.dart';

import '../fakes/fakes.dart';
import 'helpers.dart';

void main() {
  testWidgets('Sign in arms the session and the site opens; End clears it', (
    tester,
  ) async {
    final opened = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        opened.add(call);
        return true;
      },
    );
    final bridge = FakeFillSessionBridge();
    final entry = makeEntry(
      id: 'g',
      title: 'Google',
      username: 'me@gmail.com',
      password: 'pw',
      url: 'accounts.google.com',
      totp: const TotpConfig(secret: 'GEZDGNBVGY3TQOJQ'),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => FakeVaultNotifier([entry])),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
          fillSessionBridgeProvider.overrideWithValue(bridge),
        ],
        child: MaterialApp(home: EntryDetailScreen(entryId: entry.id)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Ready to fill for 2 min'), findsNothing);

    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bridge.armedEntryId, 'g');
    expect(opened, isNotEmpty);
    expect(find.text('Ready to fill for 2 min'), findsOneWidget);

    await tester.tap(find.text('End'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(bridge.armedEntryId, isNull);
    expect(find.text('Ready to fill for 2 min'), findsNothing);

    // The armed state also ends on its own after two minutes.
    await tester.tap(find.text('Sign in'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    expect(find.text('Ready to fill for 2 min'), findsNothing);
  });

  testWidgets('an entry without a website has no Sign in button', (
    tester,
  ) async {
    final entry = makeEntry(id: 'n', title: 'No site', password: 'pw', url: '');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          vaultEntriesProvider.overrideWith(() => FakeVaultNotifier([entry])),
          clockProvider.overrideWithValue(FixedClock(DateTime(2026, 7, 5))),
          fillSessionBridgeProvider.overrideWithValue(FakeFillSessionBridge()),
        ],
        child: MaterialApp(home: EntryDetailScreen(entryId: entry.id)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Copy password'), findsOneWidget);
  });
}
